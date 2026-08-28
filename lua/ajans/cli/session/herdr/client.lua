local bit = require("bit")

local M = {}

--- Luv accepts this minimal spawn shape, but its LuaLS metadata currently
--- marks every platform-specific option as required.
---@class ajans.uv.SpawnOptions
---@field args string[]
---@field detached boolean
---@field env string[]
---@field stdio uv.spawn.options.stdio[]

---@alias ajans.uv.Spawn fun(path:string, options:ajans.uv.SpawnOptions, on_exit:uv.spawn.on_exit):(uv.uv_process_t?, integer|string?)

M.TIMEOUT = 5000
M.REQUEST_TIMEOUT_GRACE = 1000
M.MAX_RESPONSE_BYTES = 1024 * 1024
M._request_id = 0
M._fs_stat = vim.uv.fs_stat
M._fs_lstat = vim.uv.fs_lstat
M._fs_realpath = vim.uv.fs_realpath
M._getuid = vim.uv.getuid

local SERVER_ENV_KEYS = {
  "HOME",
  "LANG",
  "LC_ALL",
  "LOGNAME",
  "PATH",
  "SHELL",
  "TEMP",
  "TERM",
  "TMP",
  "TMPDIR",
  "USER",
  "XDG_CACHE_HOME",
  "XDG_CONFIG_HOME",
  "XDG_DATA_HOME",
  "XDG_RUNTIME_DIR",
  "XDG_STATE_HOME",
  "HERDR_CONFIG_PATH",
  "HERDR_SESSION",
  "HERDR_SOCKET_PATH",
}

---@param cmd string[]
---@return boolean
function M.is_sensitive(cmd)
  return cmd[1] == "herdr"
    and (
      (cmd[2] == "workspace" and cmd[3] == "create")
      or (cmd[2] == "tab" and cmd[3] == "create")
      or (cmd[2] == "pane" and (cmd[3] == "split" or cmd[3] == "send-text"))
      or (cmd[2] == "agent" and cmd[3] == "start")
    )
end

---@return table?, string?
function M._status()
  local result = vim.system({ "herdr", "status", "server", "--json" }, { text = true }):wait(M.TIMEOUT)
  if result.code ~= 0 then
    return nil, result.stderr ~= "" and result.stderr or result.stdout
  end
  local ok, status = pcall(vim.json.decode, result.stdout or "")
  if not ok or type(status) ~= "table" then
    return nil, "Herdr status returned malformed JSON"
  end
  return status
end

---@param path string
---@param payload string
---@param timeout? integer
---@return string?, string?
function M._exchange(path, payload, timeout)
  local pipe = assert(vim.uv.new_pipe(false))
  local output = ""
  local done = false
  local failure

  local function close()
    if not pipe:is_closing() then
      pcall(pipe.read_stop, pipe)
      pipe:close()
    end
  end

  pipe:connect(path, function(connect_error)
    if connect_error then
      failure = tostring(connect_error)
      done = true
      close()
      return
    end
    pipe:read_start(function(read_error, chunk)
      if read_error then
        failure = tostring(read_error)
        done = true
        close()
      elseif chunk then
        if #output + #chunk > M.MAX_RESPONSE_BYTES then
          failure = "Herdr API response exceeded the size limit"
          done = true
          close()
          return
        end
        output = output .. chunk
        if output:find("\n", 1, true) then
          done = true
          close()
        end
      else
        done = true
        close()
      end
    end)
    pipe:write(payload .. "\n", function(write_error)
      if write_error and not done then
        failure = tostring(write_error)
        done = true
        close()
      end
    end)
  end)

  if not vim.wait(timeout or M.TIMEOUT, function()
    return done
  end, 10) then
    failure = "Herdr API request timed out"
    close()
  end
  if failure then
    return nil, failure
  end
  local line = output:match("^([^\n]+)")
  return line ~= "" and line or nil, line and nil or "Herdr API returned an empty response"
end

---@param path string
---@return boolean, string?, string?
function M.validate_socket(path)
  local link_stat = M._fs_lstat(path)
  if type(link_stat) ~= "table" or link_stat.type == "link" then
    return false, "Herdr API path is not a local socket"
  end

  -- Resolve directory aliases such as macOS `/tmp -> /private/tmp`, while
  -- retaining lstat above so the socket entry itself can never be a symlink.
  local parent = vim.fs.dirname(path)
  local resolved_parent = M._fs_realpath(parent)
  if type(resolved_parent) ~= "string" then
    return false, "Herdr API socket parent is not a trusted directory"
  end
  local resolved_path = vim.fs.joinpath(resolved_parent, vim.fs.basename(path))
  local resolved_link_stat = M._fs_lstat(resolved_path)
  local stat = M._fs_stat(resolved_path)
  if
    type(resolved_link_stat) ~= "table"
    or resolved_link_stat.type == "link"
    or type(stat) ~= "table"
    or stat.type ~= "socket"
  then
    return false, "Herdr API path is not a local socket"
  end

  local uid = M._getuid and M._getuid()
  if uid and stat.uid ~= uid then
    return false, "Herdr API socket is owned by another user"
  end
  if type(stat.mode) ~= "number" or bit.band(stat.mode, 0x3f) ~= 0 then
    return false, "Herdr API socket permits group or other access"
  end
  for resolved_ancestor in vim.fs.parents(resolved_path) do
    local ancestor_link_stat = M._fs_lstat(resolved_ancestor)
    local ancestor_stat = M._fs_stat(resolved_ancestor)
    if
      type(ancestor_link_stat) ~= "table"
      or ancestor_link_stat.type == "link"
      or type(ancestor_stat) ~= "table"
      or ancestor_stat.type ~= "directory"
      or type(ancestor_stat.mode) ~= "number"
      or (uid and ancestor_stat.uid ~= uid and ancestor_stat.uid ~= 0)
    then
      return false, "Herdr API socket parent is not a trusted directory"
    end
    local writable = bit.band(ancestor_stat.mode, 0x12) ~= 0
    local sticky = bit.band(ancestor_stat.mode, 0x200) ~= 0
    if writable and not sticky then
      return false, "Herdr API socket parent permits replacement by another user"
    end
  end
  return true, nil, resolved_path
end

---@param known_status? table
---@return string?, string?
function M.trusted_socket(known_status)
  local status, status_error = known_status, nil
  if not status then
    status, status_error = M._status()
  end
  if not status then
    return nil, status_error or "Unable to query Herdr server"
  end
  local socket = status.socket or status.socket_path
  if status.running ~= true or type(socket) ~= "string" or socket == "" then
    return nil, "Herdr server status is missing a running API socket"
  end
  if status.compatible == false then
    return nil, "Herdr server is not compatible with the active client"
  end
  local safe, socket_error, validated_socket = M.validate_socket(socket)
  if not safe then
    return nil, socket_error or "Herdr API socket is unsafe"
  end
  return validated_socket or socket
end

---@param method string
---@param params table
---@param timeout? integer
---@return vim.SystemCompleted
function M.request(method, params, timeout)
  local socket, socket_error = M.trusted_socket()
  if not socket then
    return { code = 1, signal = 0, stdout = "", stderr = socket_error }
  end

  M._request_id = M._request_id + 1
  local request_id = "ajans:" .. M._request_id
  local payload = vim.json.encode({
    id = request_id,
    method = method,
    params = params,
  })
  local exchanged, response, exchange_error = pcall(M._exchange, socket, payload, timeout or M.TIMEOUT)
  if not exchanged then
    exchange_error = tostring(response)
    response = nil
  end
  if not response then
    return { code = 1, signal = 0, stdout = "", stderr = exchange_error or "Herdr API request failed" }
  end
  local ok, decoded = pcall(vim.json.decode, response)
  if not ok or type(decoded) ~= "table" then
    return { code = 1, signal = 0, stdout = "", stderr = "Herdr API returned malformed JSON" }
  end
  if decoded.id ~= request_id then
    return { code = 1, signal = 0, stdout = "", stderr = "Herdr API returned a mismatched response ID" }
  end
  local code = type(decoded.error) == "table" and 1 or 0
  return {
    code = code,
    signal = 0,
    stdout = code == 0 and response .. "\n" or "",
    stderr = code == 1 and response .. "\n" or "",
  }
end

---@param value string
---@return string?, string?
local function env_pair(value)
  local split = value:find("=", 1, true)
  if not split or split == 1 then
    return
  end
  return value:sub(1, split - 1), value:sub(split + 1)
end

---@return vim.SystemCompleted
local function invalid_sensitive_command()
  return { code = 2, signal = 0, stdout = "", stderr = "invalid sensitive Herdr command" }
end

---@param cmd string[]
---@param method string
---@param fields table<string,string>
---@return vim.SystemCompleted
local function create(cmd, method, fields)
  local params = { env = {}, focus = false }
  local index = 4
  while index <= #cmd do
    local flag = cmd[index]
    if flag == "--no-focus" then
      params.focus = false
      index = index + 1
    elseif flag == "--focus" then
      params.focus = true
      index = index + 1
    elseif flag == "--env" then
      local assignment = cmd[index + 1]
      if type(assignment) ~= "string" then
        return invalid_sensitive_command()
      end
      local key, value = env_pair(assignment)
      if not key then
        return invalid_sensitive_command()
      end
      params.env[key] = value
      index = index + 2
    else
      local field = fields[flag]
      local value = cmd[index + 1]
      if not field or type(value) ~= "string" then
        return invalid_sensitive_command()
      end
      params[field] = value
      index = index + 2
    end
  end
  return M.request(method, params)
end

---@param cmd string[]
---@return vim.SystemCompleted
local function start(cmd)
  local params = { name = cmd[4], args = {} }
  local index = 5
  while index <= #cmd and cmd[index] ~= "--" do
    local flag = cmd[index]
    local value = cmd[index + 1]
    if type(value) ~= "string" then
      return invalid_sensitive_command()
    elseif flag == "--kind" then
      params.kind = value
    elseif flag == "--pane" then
      params.pane_id = value
    elseif flag == "--timeout" then
      params.timeout_ms = tonumber(value)
      if not params.timeout_ms then
        return invalid_sensitive_command()
      end
    else
      return invalid_sensitive_command()
    end
    index = index + 2
  end
  if cmd[index] == "--" then
    params.args = vim.list_slice(cmd, index + 1)
  end
  if type(params.name) ~= "string" or type(params.kind) ~= "string" or type(params.pane_id) ~= "string" then
    return invalid_sensitive_command()
  end
  local timeout = params.timeout_ms and params.timeout_ms + M.REQUEST_TIMEOUT_GRACE or nil
  return M.request("agent.start", params, timeout)
end

---@param cmd string[]
---@return vim.SystemCompleted
function M.run(cmd)
  if cmd[2] == "workspace" and cmd[3] == "create" then
    return create(cmd, "workspace.create", { ["--cwd"] = "cwd", ["--label"] = "label" })
  end
  if cmd[2] == "tab" and cmd[3] == "create" then
    return create(cmd, "tab.create", {
      ["--workspace"] = "workspace_id",
      ["--cwd"] = "cwd",
      ["--label"] = "label",
    })
  end
  if cmd[2] == "pane" and cmd[3] == "split" then
    return create(cmd, "pane.split", {
      ["--pane"] = "target_pane_id",
      ["--workspace"] = "workspace_id",
      ["--direction"] = "direction",
      ["--cwd"] = "cwd",
    })
  end
  if cmd[2] == "agent" and cmd[3] == "start" then
    return start(cmd)
  end
  if cmd[2] == "pane" and cmd[3] == "send-text" and type(cmd[4]) == "string" and type(cmd[5]) == "string" then
    return M.request("pane.send_text", { pane_id = cmd[4], text = table.concat(cmd, " ", 5) })
  end
  return { code = 2, signal = 0, stdout = "", stderr = "unsupported sensitive Herdr command" }
end

---@return string[]
function M.server_env()
  local current = vim.fn.environ()
  local env = {}
  for _, key in ipairs(SERVER_ENV_KEYS) do
    local value = current[key]
    if type(value) == "string" then
      env[#env + 1] = key .. "=" .. value
    end
  end
  return env
end

---@return boolean, string?
function M.spawn_server()
  local handle
  local spawn_error
  local spawn = vim.uv.spawn --[[@as ajans.uv.Spawn]]
  handle, spawn_error = spawn("herdr", {
    args = { "server" },
    detached = true,
    env = M.server_env(),
    stdio = { nil, nil, nil },
  }, function()
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)
  if not handle then
    return false, tostring(spawn_error or "unable to spawn Herdr server")
  end
  -- Detachment alone creates a process group; unref prevents the long-lived
  -- server handle from keeping Neovim's event loop alive.
  handle:unref()
  return true
end

return M
