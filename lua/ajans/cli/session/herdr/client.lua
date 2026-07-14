local bit = require("bit")

local M = {}

M.TIMEOUT = 5000
M.MAX_RESPONSE_BYTES = 1024 * 1024
M._request_id = 0
M._fs_stat = vim.uv.fs_stat
M._fs_lstat = vim.uv.fs_lstat
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
      (cmd[2] == "agent" and (cmd[3] == "start" or cmd[3] == "send"))
      or (cmd[2] == "pane" and cmd[3] == "send-text")
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
---@return boolean, string?
function M.validate_socket(path)
  local link_stat = M._fs_lstat(path)
  local stat = M._fs_stat(path)
  if type(link_stat) ~= "table" or link_stat.type == "link" or type(stat) ~= "table" or stat.type ~= "socket" then
    return false, "Herdr API path is not a local socket"
  end
  local uid = M._getuid and M._getuid()
  if uid and stat.uid ~= uid then
    return false, "Herdr API socket is owned by another user"
  end
  if type(stat.mode) ~= "number" or bit.band(stat.mode, 0x3f) ~= 0 then
    return false, "Herdr API socket permits group or other access"
  end
  for parent in vim.fs.parents(path) do
    local parent_link_stat = M._fs_lstat(parent)
    local parent_stat = M._fs_stat(parent)
    if
      type(parent_link_stat) ~= "table"
      or parent_link_stat.type == "link"
      or type(parent_stat) ~= "table"
      or parent_stat.type ~= "directory"
      or type(parent_stat.mode) ~= "number"
      or (uid and parent_stat.uid ~= uid and parent_stat.uid ~= 0)
    then
      return false, "Herdr API socket parent is not a trusted directory"
    end
    local writable = bit.band(parent_stat.mode, 0x12) ~= 0
    local sticky = bit.band(parent_stat.mode, 0x200) ~= 0
    if writable and not sticky then
      return false, "Herdr API socket parent permits replacement by another user"
    end
  end
  return true
end

---@return string?, string?
function M.trusted_socket()
  local status, status_error = M._status()
  if not status then
    return nil, status_error or "Unable to query Herdr server"
  end
  local socket = status.socket or status.socket_path
  if status.running ~= true or type(socket) ~= "string" or socket == "" then
    return nil, "Herdr server status is missing a running API socket"
  end
  if status.compatible == false or status.restart_needed == true then
    return nil, "Herdr server is not compatible with the active client"
  end
  local safe, socket_error = M.validate_socket(socket)
  if not safe then
    return nil, socket_error or "Herdr API socket is unsafe"
  end
  return socket
end

---@param method string
---@param params table
---@return vim.SystemCompleted
function M.request(method, params)
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
  local exchanged, response, exchange_error = pcall(M._exchange, socket, payload, M.TIMEOUT)
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
---@return string, string
local function env_pair(value)
  local split = assert(value:find("=", 1, true), "invalid Herdr environment assignment")
  return value:sub(1, split - 1), value:sub(split + 1)
end

---@param cmd string[]
---@return vim.SystemCompleted
local function start(cmd)
  local params = { env = {}, focus = false }
  local index = 4
  params.name = cmd[index]
  index = index + 1
  while index <= #cmd and cmd[index] ~= "--" do
    local flag = cmd[index]
    if flag == "--no-focus" then
      params.focus = false
      index = index + 1
    elseif flag == "--focus" then
      params.focus = true
      index = index + 1
    elseif flag == "--env" then
      local key, value = env_pair(assert(cmd[index + 1], "missing Herdr environment assignment"))
      params.env[key] = value
      index = index + 2
    else
      local fields = {
        ["--cwd"] = "cwd",
        ["--workspace"] = "workspace_id",
        ["--tab"] = "tab_id",
        ["--split"] = "split",
      }
      local field = fields[flag]
      if not field or cmd[index + 1] == nil then
        return { code = 2, signal = 0, stdout = "", stderr = "invalid Herdr agent start command" }
      end
      params[field] = cmd[index + 1]
      index = index + 2
    end
  end
  if type(params.name) ~= "string" or cmd[index] ~= "--" or index == #cmd then
    return { code = 2, signal = 0, stdout = "", stderr = "invalid Herdr agent start command" }
  end
  params.argv = vim.list_slice(cmd, index + 1)
  return M.request("agent.start", params)
end

---@param cmd string[]
---@return vim.SystemCompleted
function M.run(cmd)
  if cmd[2] == "agent" and cmd[3] == "start" then
    return start(cmd)
  end
  if cmd[2] == "agent" and cmd[3] == "send" and type(cmd[4]) == "string" and type(cmd[5]) == "string" then
    return M.request("agent.send", { target = cmd[4], text = table.concat(cmd, " ", 5) })
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
  handle, spawn_error = vim.uv.spawn("herdr", {
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
