local Client = require("ajans.cli.session.herdr.client")
local Config = require("ajans.config")
local Discovery = require("ajans.cli.session.herdr.discovery")
local Layout = require("ajans.cli.session.herdr.layout")
local Util = require("ajans.util")

---@class ajans.cli.muxer.Herdr: ajans.cli.Session
---@field herdr_terminal_id string
---@field herdr_pane_id string
---@field herdr_workspace_id string
---@field herdr_tab_id string
---@field herdr_agent boolean
local M = {}
M.__index = M

M.MIN_VERSION = { 0, 7, 0 }
M.MIN_VERSION_STRING = "0.7.0"
M.SNAPSHOT_VERSION = { 0, 7, 2 }
M.STARTUP_TIMEOUT = 5000
M.STARTUP_INTERVAL = 100
M.COMMAND_TIMEOUT = 5000
M.LIVENESS_TIMEOUT = 250
M.LIVENESS_ERROR_INTERVAL = 30000
M.DISCOVERY_TIMEOUT = 5000
M.PROCESS_INFO_CONCURRENCY = 8
M.MAX_DUMP_LINES = 1000
M.SEND_CHUNK_BYTES = 24 * 1024

local AGENT_PREFIX = "ajans:"

---@param cmd string[]
---@param opts? vim.SystemOpts
---@return vim.SystemCompleted
function M._run(cmd, opts)
  if Client.is_sensitive(cmd) then
    return Client.run(cmd)
  end
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  local timeout = opts.timeout or M.COMMAND_TIMEOUT
  opts.timeout = nil
  return vim.system(cmd, opts):wait(timeout)
end

---@param commands string[][]
---@return vim.SystemCompleted[]
function M._run_many(commands)
  local results = {}
  local started = vim.uv.hrtime()
  local index = 1
  while index <= #commands do
    local elapsed = math.floor((vim.uv.hrtime() - started) / 1e6)
    local remaining = M.DISCOVERY_TIMEOUT - elapsed
    if remaining <= 0 then
      for pending = index, #commands do
        results[pending] = { code = 124, signal = 15, stdout = "", stderr = "Herdr discovery timed out" }
      end
      break
    end

    local jobs = {}
    local last = math.min(index + M.PROCESS_INFO_CONCURRENCY - 1, #commands)
    for command_index = index, last do
      jobs[#jobs + 1] = {
        index = command_index,
        job = vim.system(commands[command_index], { text = true }),
      }
    end
    for job_index, item in ipairs(jobs) do
      elapsed = math.floor((vim.uv.hrtime() - started) / 1e6)
      remaining = M.DISCOVERY_TIMEOUT - elapsed
      if remaining <= 0 then
        for pending = job_index, #jobs do
          pcall(jobs[pending].job.kill, jobs[pending].job, 15)
          results[jobs[pending].index] = {
            code = 124,
            signal = 15,
            stdout = "",
            stderr = "Herdr discovery timed out",
          }
        end
        break
      end
      results[item.index] = item.job:wait(remaining)
    end
    index = last + 1
  end
  return results
end

---@param cmd string[]
---@param opts? vim.SystemOpts
---@return vim.SystemObj
function M._spawn(cmd, opts)
  if vim.deep_equal(cmd, { "herdr", "server" }) then
    return Client.spawn_server()
  end
  return vim.system(cmd, opts)
end

---@param timeout integer
---@param condition fun():boolean
---@param interval integer
---@return boolean
function M._wait(timeout, condition, interval)
  return vim.wait(timeout, condition, interval)
end

---@param version string?
---@return integer[]?
function M.parse_version(version)
  if type(version) ~= "string" then
    return
  end
  local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
  if not major then
    return
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

---@param version integer[]
---@param minimum? integer[]
---@return boolean
function M.version_at_least(version, minimum)
  minimum = minimum or M.MIN_VERSION
  for index = 1, 3 do
    local found = version[index] or 0
    local required = minimum[index] or 0
    if found ~= required then
      return found > required
    end
  end
  return true
end

---@return string?
function M.version()
  if vim.fn.executable("herdr") ~= 1 then
    return
  end
  local ok, result = pcall(M._run, { "herdr", "--version" })
  if not ok or result.code ~= 0 then
    return
  end
  return result.stdout and result.stdout:match("(%d+%.%d+%.%d+)") or nil
end

---@return boolean, string?, string?
function M.validate()
  if vim.fn.has("win32") == 1 then
    return false, "Herdr backend is supported on macOS and Linux; Windows is not supported"
  end
  if vim.fn.executable("herdr") ~= 1 then
    return false, "Herdr backend requires `herdr` >= " .. M.MIN_VERSION_STRING .. ", but `herdr` is not installed"
  end
  local version = M.version()
  local parsed = M.parse_version(version)
  if not parsed then
    return false, "Unable to determine the installed Herdr version from `herdr --version`"
  end
  if not M.version_at_least(parsed) then
    return false,
      ("Herdr backend requires `herdr` >= %s (found %s); upgrade Herdr and restart its server"):format(
        M.MIN_VERSION_STRING,
        version
      )
  end
  return true, nil, version
end

---@return boolean
function M.is_available()
  return M.validate()
end

---@param args string[]
---@return string[]
local function herdr_cmd(args)
  local cmd = { "herdr" }
  vim.list_extend(cmd, args)
  return cmd
end

---@param value string?
---@return any?
local function decode(value)
  if type(value) ~= "string" or value == "" then
    return
  end
  local ok, decoded = pcall(vim.json.decode, value)
  return ok and decoded or nil
end

---@param result vim.SystemCompleted
---@return string
local function error_message(result)
  local value = decode(result.stderr) or decode(result.stdout)
  local body = type(value) == "table" and (value.error or value) or nil
  if type(body) == "table" then
    local code = body.code and tostring(body.code) or "herdr_error"
    local message = body.message and tostring(body.message) or "Herdr command failed"
    return code .. ": " .. message
  end
  local message = result.stderr ~= "" and result.stderr or result.stdout
  message = type(message) == "string" and vim.trim(message) or ""
  return message ~= "" and message or "Herdr command failed"
end

---@param message string
---@return boolean
local function stopped_error(message)
  message = message:lower()
  return message:find("connection refused", 1, true) ~= nil
    or message:find("failed to connect", 1, true) ~= nil
    or message:find("server is not running", 1, true) ~= nil
    or message:find("no such file", 1, true) ~= nil
    or message:find("not_running", 1, true) ~= nil
end

---@class ajans.herdr.ExecOpts
---@field notify? boolean
---@field stopped_ok? boolean
---@field redact? boolean
---@field system? vim.SystemOpts

---@param cmd string[]
---@param redact? boolean
---@return string
local function display_command(cmd, redact)
  if not redact then
    return table.concat(cmd, " ")
  end
  local shown = vim.list_slice(cmd, 1, math.min(4, #cmd))
  shown[#shown + 1] = "<redacted>"
  return table.concat(shown, " ")
end

---@param args string[]
---@param opts? ajans.herdr.ExecOpts
---@return vim.SystemCompleted?, string?
local function execute(args, opts)
  opts = opts or {}
  local cmd = herdr_cmd(args)
  local rendered = display_command(cmd, opts.redact)
  local system_opts = vim.tbl_extend("force", { text = true }, opts.system or {})
  local ok, result = pcall(M._run, cmd, system_opts)
  if not ok then
    local message = tostring(result)
    if opts.notify ~= false then
      Util.error(("Failed to execute Herdr command: `%s`\n%s"):format(rendered, message))
    end
    return nil, message
  end
  if result.code == 0 then
    return result
  end
  local message = error_message(result)
  if opts.stopped_ok and stopped_error(message) then
    return nil, "stopped"
  end
  if opts.notify ~= false then
    Util.error(("Herdr command failed: `%s`\n%s"):format(rendered, message))
  end
  return nil, message
end

---@param args string[]
---@param opts? ajans.herdr.ExecOpts
---@return table?, string?
function M.request(args, opts)
  local result, err = execute(args, opts)
  if not result then
    return nil, err
  end
  local value = decode(result.stdout)
  if type(value) ~= "table" then
    if not opts or opts.notify ~= false then
      Util.error(
        ("Herdr command returned malformed JSON: `%s`"):format(display_command(herdr_cmd(args), opts and opts.redact))
      )
    end
    return nil, "malformed JSON"
  end
  if type(value.error) == "table" then
    local message = error_message({ code = 1, stdout = result.stdout, stderr = "", signal = 0 })
    if not opts or opts.notify ~= false then
      Util.error(
        ("Herdr command failed: `%s`\n%s"):format(display_command(herdr_cmd(args), opts and opts.redact), message)
      )
    end
    return nil, message
  end
  if type(value.result) ~= "table" then
    if not opts or opts.notify ~= false then
      Util.error(
        ("Herdr JSON response is missing `result`: `%s`"):format(display_command(herdr_cmd(args), opts and opts.redact))
      )
    end
    return nil, "missing `result`"
  end
  return value.result
end

---@param args string[]
---@param opts? ajans.herdr.ExecOpts
---@return string?, string?
function M.command(args, opts)
  local result, err = execute(args, opts)
  return result and result.stdout or nil, err
end

---@return table?, string?
function M.server_status()
  local ok, result = pcall(M._run, { "herdr", "status", "server", "--json" }, { text = true })
  if not ok then
    return nil, tostring(result)
  end
  if result.code ~= 0 then
    return nil, error_message(result)
  end
  local value = decode(result.stdout)
  if type(value) ~= "table" or type(value.running) ~= "boolean" then
    return nil, "Herdr status returned malformed JSON"
  end
  return value
end

---@param status table
---@return string?
local function server_incompatibility(status)
  if status.running and status.compatible == false then
    return "The running Herdr server is incompatible with the installed client; restart the Herdr server"
  end
  if status.running and status.restart_needed == true then
    return "The running Herdr server uses a different version; restart the Herdr server"
  end
end

---@return boolean
function M.is_server_running()
  local status = M.server_status()
  return status ~= nil and status.running == true and server_incompatibility(status) == nil
end

---@return boolean
function M.is_usable()
  local valid = M.validate()
  if not valid then
    return false
  end
  local status = M.server_status()
  return status ~= nil and server_incompatibility(status) == nil
end

---@return boolean
function M.ensure_server()
  local valid, err = M.validate()
  if not valid then
    Util.error(err or "Herdr is unavailable")
    return false
  end
  local status, status_err = M.server_status()
  if not status then
    Util.error(status_err or "Unable to query the Herdr server")
    return false
  end
  local incompatible = server_incompatibility(status)
  if incompatible then
    Util.error(incompatible)
    return false
  end
  if status.running then
    return true
  end
  local ok, spawned = pcall(M._spawn, { "herdr", "server" }, {
    text = true,
    detach = true,
    stdin = false,
    stdout = false,
    stderr = false,
  })
  if not ok or not spawned then
    Util.error("Failed to start the Herdr server")
    return false
  end
  if not M._wait(M.STARTUP_TIMEOUT, M.is_server_running, M.STARTUP_INTERVAL) then
    local _, startup_status_err = M.server_status()
    local detail = startup_status_err or "check `herdr status server --json` and the Herdr server log"
    Util.error(("Herdr server did not become ready within %dms: %s"):format(M.STARTUP_TIMEOUT, detail))
    return false
  end
  return true
end

M.tool_name_for_label = Discovery.tool_name_for_label
local process_pids = Discovery.process_pids
local to_proc = Discovery.to_proc

---@param pane table
---@return table?
local function pane_process_info(pane)
  return Discovery.pane_process_info(M, pane)
end

---@return boolean
function M.supports_snapshot()
  local version = M.parse_version(M.version())
  return version ~= nil and M.version_at_least(version, M.SNAPSHOT_VERSION)
end

---@return table?, string?
function M.snapshot()
  return Discovery.snapshot(M)
end

---@return ajans.cli.session.State[], boolean
function M.sessions()
  return Discovery.sessions(M)
end

function M:init()
  if self.started then
    self.external = vim.env.HERDR_ENV == "1" and self.herdr_placement ~= "workspace"
  else
    self.external = vim.env.HERDR_ENV == "1" and Config.cli.mux.create ~= "terminal"
  end
  self.priority = self.external and 10 or 50
end

---@return string
function M:agent_name()
  return ("%s%s %s"):format(AGENT_PREFIX, self.tool.name, vim.fn.sha256(self.cwd):sub(1, 12))
end

---@return string[], string[]
function M:launch_argv()
  local argv = vim.deepcopy(self.tool.cmd)
  local env_args = {}
  local unset = {}
  local keys = vim.tbl_keys(self.tool.env or {})
  table.sort(keys)
  for _, key in ipairs(keys) do
    local value = self.tool.env[key]
    if value == false then
      unset[#unset + 1] = key
    else
      vim.list_extend(env_args, { "--env", ("%s=%s"):format(key, tostring(value)) })
    end
  end
  if #unset > 0 then
    local wrapped = { "env" }
    for _, key in ipairs(unset) do
      vim.list_extend(wrapped, { "-u", key })
    end
    wrapped[#wrapped + 1] = "--"
    vim.list_extend(wrapped, argv)
    argv = wrapped
  end
  return argv, env_args
end

---@type fun(kind:"workspace"|"tab"|"pane", id:string):boolean
local rollback

---@param workspace_id string
---@param tab_id string
---@param split "right"|"down"
---@return table?
function M:launch(workspace_id, tab_id, split)
  local argv, env_args = self:launch_argv()
  local cmd = {
    "agent",
    "start",
    self:agent_name(),
    "--cwd",
    self.cwd,
    "--workspace",
    workspace_id,
    "--tab",
    tab_id,
    "--split",
    split,
    "--no-focus",
  }
  vim.list_extend(cmd, env_args)
  cmd[#cmd + 1] = "--"
  vim.list_extend(cmd, argv)
  local result = M.request(cmd, { redact = true })
  local agent = result and result.agent
  if
    type(agent) ~= "table"
    or type(agent.terminal_id) ~= "string"
    or type(agent.pane_id) ~= "string"
    or type(agent.workspace_id) ~= "string"
    or type(agent.tab_id) ~= "string"
  then
    if type(agent) == "table" and type(agent.pane_id) == "string" then
      rollback("pane", agent.pane_id)
    end
    if result ~= nil then
      Util.error("Herdr agent start response is missing stable terminal, pane, workspace, or tab IDs")
    end
    return
  end
  return agent
end

---@param agent table
---@param placement "workspace"|"tab"|"split"
function M:set_agent(agent, placement)
  self.id = "herdr " .. agent.terminal_id
  self.identity = "herdr:" .. agent.terminal_id
  self.herdr_terminal_id = agent.terminal_id
  self.herdr_pane_id = agent.pane_id
  self.herdr_workspace_id = agent.workspace_id
  self.herdr_tab_id = agent.tab_id
  self.herdr_agent = true
  self.herdr_name = self:agent_name()
  self.herdr_placement = placement
  self.mux_session = agent.workspace_id
  self.cwd = agent.foreground_cwd or agent.cwd or self.cwd
  local info = pane_process_info({ pane_id = agent.pane_id })
  self.pids = process_pids(info)
  self.started = true
  self.external = placement ~= "workspace"
  self.priority = self.external and 10 or 50
end

---@param kind "workspace"|"tab"|"pane"
---@param id string
---@return boolean
rollback = function(kind, id)
  local args = { kind, "close", id }
  for _ = 1, 2 do
    if M.command(args, { notify = false }) ~= nil then
      return true
    end
  end
  Util.error(("Failed to clean up Herdr %s `%s`; run `herdr %s close %s` manually"):format(kind, id, kind, id))
  return false
end

---@return ajans.cli.terminal.Cmd? cmd
---@return boolean started
function M:start_workspace()
  local result = M.request({
    "workspace",
    "create",
    "--cwd",
    self.cwd,
    "--label",
    self:agent_name(),
    "--no-focus",
  })
  if not result then
    return nil, false
  end
  local workspace_id = result.workspace and result.workspace.workspace_id
  local tab_id = result.tab and result.tab.tab_id
  local root_pane_id = result.root_pane and result.root_pane.pane_id
  if type(workspace_id) ~= "string" or type(tab_id) ~= "string" or type(root_pane_id) ~= "string" then
    if type(workspace_id) == "string" then
      rollback("workspace", workspace_id)
    end
    Util.error("Herdr workspace creation response is missing stable workspace, tab, or pane IDs")
    return nil, false
  end
  local agent = self:launch(workspace_id, tab_id, "right")
  if not agent then
    rollback("workspace", workspace_id)
    return nil, false
  end
  local closed = M.command({ "pane", "close", root_pane_id })
  if closed == nil then
    rollback("workspace", workspace_id)
    return nil, false
  end
  self:set_agent(agent, "workspace")
  return { cmd = { "herdr", "agent", "attach", self.herdr_terminal_id } }, true
end

---@return boolean
function M:have_host_ids()
  if not vim.env.HERDR_WORKSPACE_ID or not vim.env.HERDR_TAB_ID then
    Util.error("Herdr external creation requires `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID`")
    return false
  end
  return true
end

---@return nil
---@return boolean started
function M:start_tab()
  if not self:have_host_ids() then
    return nil, false
  end
  local result = M.request({
    "tab",
    "create",
    "--workspace",
    vim.env.HERDR_WORKSPACE_ID,
    "--cwd",
    self.cwd,
    "--label",
    self:agent_name(),
    "--no-focus",
  })
  if not result then
    return nil, false
  end
  local tab_id = result.tab and result.tab.tab_id
  local root_pane_id = result.root_pane and result.root_pane.pane_id
  if type(tab_id) ~= "string" or type(root_pane_id) ~= "string" then
    if type(tab_id) == "string" then
      rollback("tab", tab_id)
    end
    Util.error("Herdr tab creation response is missing stable tab or pane IDs")
    return nil, false
  end
  local agent = self:launch(vim.env.HERDR_WORKSPACE_ID, tab_id, "right")
  if not agent then
    rollback("tab", tab_id)
    return nil, false
  end
  local closed = M.command({ "pane", "close", root_pane_id })
  if closed == nil then
    rollback("tab", tab_id)
    return nil, false
  end
  self:set_agent(agent, "tab")
  Util.info(("Started **%s** in a new Herdr tab"):format(self.tool.name))
  return nil, true
end

---@param pane_id string
---@param direction "right"|"down"
---@return boolean
function M:size_split(pane_id, direction)
  local result = M.request({ "pane", "layout", "--pane", pane_id })
  local layout = result and result.layout
  local valid, layout_error = Layout.validate(layout)
  if not valid then
    Util.error("Herdr pane layout is invalid: " .. layout_error)
    return false
  end
  local pane = Layout.pane(layout, pane_id)
  local split = Layout.containing_split(layout, pane_id, direction)
  if not pane or not split then
    Util.error("Herdr pane layout did not include the new split")
    return false
  end

  local size = Config.cli.mux.split.size
  local desired = size
  local dimension = direction == "right" and split.rect.width or split.rect.height
  if size > 1 then
    desired = size / dimension
  end
  if desired < 0.1 or desired > 0.9 then
    Util.error(("Herdr split size %s falls outside the supported 10%%-90%% layout range"):format(size))
    return false
  end

  local current = Layout.share(split, pane)
  local amount = math.abs(desired - current)
  if amount < 0.000001 then
    return true
  end
  local desired_ratio = Layout.is_second(split, pane) and 1 - desired or desired
  local ratio_delta = desired_ratio - split.ratio
  local resize_direction = ratio_delta > 0 and (direction == "right" and "right" or "down")
    or (direction == "right" and "left" or "up")
  local target_pane = Layout.resize_target(layout, split.id, pane_id, resize_direction)
  if not target_pane then
    Util.error("Herdr cannot resize the new pane without targeting a different split boundary")
    return false
  end

  local resize = M.request({
    "pane",
    "resize",
    "--pane",
    target_pane,
    "--direction",
    resize_direction,
    "--amount",
    ("%.6g"):format(math.abs(ratio_delta)),
  })
  if not resize or type(resize.resize) ~= "table" then
    return false
  end
  if resize.resize.changed == false then
    Util.error("Herdr reported that the requested pane resize made no layout change")
    return false
  end
  local final_layout = resize.resize.layout
  local final_valid, final_error = Layout.validate(final_layout)
  if not final_valid then
    Util.error("Herdr pane resize returned an invalid layout: " .. final_error)
    return false
  end
  local final_split = Layout.split(final_layout, split.id)
  local final_pane = Layout.pane(final_layout, pane_id)
  if not final_split or not final_pane then
    Util.error("Herdr pane resize response did not include the resized split and pane")
    return false
  end
  local actual = Layout.share(final_split, final_pane)
  local tolerance = size > 1 and (1 / dimension) or 0.01
  if math.abs(actual - desired) > tolerance then
    Util.error(("Herdr resized pane to %.3f instead of configured %.3f"):format(actual, desired))
    return false
  end
  return true
end

---@return nil
---@return boolean started
function M:start_split()
  if not self:have_host_ids() then
    return nil, false
  end
  local direction = Config.cli.mux.split.vertical and "right" or "down"
  local agent = self:launch(vim.env.HERDR_WORKSPACE_ID, vim.env.HERDR_TAB_ID, direction)
  if not agent then
    return nil, false
  end
  if not self:size_split(agent.pane_id, direction) then
    rollback("pane", agent.pane_id)
    return nil, false
  end
  self:set_agent(agent, "split")
  Util.info(("Started **%s** in a new Herdr split"):format(self.tool.name))
  return nil, true
end

---@return ajans.cli.terminal.Cmd? cmd
---@return boolean started
function M:start()
  if not M.ensure_server() then
    return nil, false
  end
  if not self.external then
    return self:start_workspace()
  elseif Config.cli.mux.create == "window" then
    return self:start_tab()
  elseif Config.cli.mux.create == "split" then
    return self:start_split()
  end
end

---@return ajans.cli.terminal.Cmd?
function M:attach()
  if self.external or not self.herdr_terminal_id then
    return
  end
  if self.herdr_agent then
    return { cmd = { "herdr", "agent", "attach", self.herdr_terminal_id } }
  end
  return { cmd = { "herdr", "terminal", "attach", self.herdr_terminal_id } }
end

function M:detach() end

---@return boolean
function M:is_running()
  local args
  if self.herdr_agent and self.herdr_terminal_id then
    args = { "agent", "get", self.herdr_terminal_id }
  elseif self.herdr_pane_id then
    args = { "pane", "get", self.herdr_pane_id }
  else
    return false
  end
  local result, err = M.request(args, {
    notify = false,
    stopped_ok = true,
    system = { timeout = M.LIVENESS_TIMEOUT },
  })
  if result then
    self._liveness_error = nil
    return true
  end
  if err == "stopped" or (err and (err:find("not_found", 1, true) or err:find("not found", 1, true))) then
    return false
  end
  local now = vim.uv.now()
  local message = err or "unknown error"
  local previous = self._liveness_error
  if not previous or previous.message ~= message or now - previous.time >= M.LIVENESS_ERROR_INTERVAL then
    Util.error("Unable to verify Herdr session liveness: " .. message)
    self._liveness_error = { message = message, time = now }
  end
  -- A transient transport failure is unknown, not proof that the pane exited.
  return true
end

function M:accepts_automated_input()
  if self.herdr_agent then
    return self:is_running()
  end
  if not self.herdr_pane_id or type(self.tool.is_proc) ~= "function" then
    return false
  end
  local info = pane_process_info({ pane_id = self.herdr_pane_id })
  if not info then
    return false
  end
  for _, process in ipairs(info.foreground_processes or {}) do
    if self.tool:is_proc(to_proc(process)) then
      return true
    end
  end
  return false
end

---@param text string
---@return string[]
local function send_chunks(text)
  local chunks = {}
  local start = 1
  while start <= #text do
    local next_start = math.min(start + M.SEND_CHUNK_BYTES, #text + 1)
    while next_start <= #text do
      local byte = text:byte(next_start)
      if not byte or byte < 0x80 or byte >= 0xC0 then
        break
      end
      next_start = next_start - 1
    end
    if next_start <= start then
      next_start = math.min(start + M.SEND_CHUNK_BYTES, #text + 1)
    end
    chunks[#chunks + 1] = text:sub(start, next_start - 1)
    start = next_start
  end
  return chunks
end

---@param text string
function M:send(text)
  if not self.herdr_pane_id or (self.herdr_agent and not self.herdr_terminal_id) then
    return false
  end
  self._send_queue = self._send_queue or {}
  self._send_queue[#self._send_queue + 1] = text
  if self._sending then
    return
  end
  self._sending = true
  self._last_send_ok = true
  while #self._send_queue > 0 do
    local next = table.remove(self._send_queue, 1)
    if self.tool.mux_focus then
      M.command({ "pane", "send-keys", self.herdr_pane_id, "escape", "[", "I" })
    end
    for _, chunk in ipairs(send_chunks(next)) do
      local result
      if self.herdr_agent then
        result = M.request({ "agent", "send", self.herdr_terminal_id, chunk }, { redact = true })
      else
        result = M.command({ "pane", "send-text", self.herdr_pane_id, chunk }, { redact = true })
      end
      if not result then
        self._last_send_ok = false
        self._send_queue = {}
        break
      end
    end
  end
  self._sending = false
  return self._last_send_ok
end

function M:submit()
  if not self.herdr_pane_id then
    return false
  end
  if self._last_send_ok == false then
    self._last_send_ok = nil
    return false
  end
  self._last_send_ok = nil
  return M.command({ "pane", "send-keys", self.herdr_pane_id, "enter" }) ~= nil
end

---@return string?
function M:dump()
  if not self.herdr_pane_id then
    return
  end
  -- Unlike Herdr's inventory/control commands, `pane read` prints the requested
  -- text directly; `--ansi` preserves terminal escape sequences.
  return M.command({
    "pane",
    "read",
    self.herdr_pane_id,
    "--source",
    "recent",
    "--lines",
    tostring(math.max(1, math.min(M.MAX_DUMP_LINES, math.floor(Config.cli.mux.dump)))),
    "--ansi",
  })
end

return M
