local Config = require("ajans.config")
local Procs = require("ajans.cli.procs")
local Util = require("ajans.util")

-- Rex is a GUI terminal and multiplexer with a persistent server; it has no
-- attachable terminal client Ajans could embed in a Neovim terminal, so this
-- backend is external-only: sessions live in Rex blocks, and Ajans drives
-- them through the `rex` CLI exactly like tmux panes, never through the
-- server socket directly.

---@class ajans.rex.TextOperation
---@field kind "text"
---@field text string
---@field ok? boolean

---@class ajans.rex.SubmitOperation
---@field kind "submit"
---@field ok? boolean

---@alias ajans.rex.InputOperation ajans.rex.TextOperation|ajans.rex.SubmitOperation

---@class ajans.cli.session.RexState: ajans.cli.session.State
---@field rex_session_id string
---@field rex_block_id string
---@field rex_pid number

---@class ajans.cli.muxer.Rex: ajans.cli.Session
---@field rex_session_id? string
---@field rex_window_id? string
---@field rex_block_id? string
---@field rex_pid? number
---@field rex_label? string
---@field _input_queue? ajans.rex.InputOperation[]
local M = {}
M.__index = M

-- Rex is pre-1.0 with build-number versions, so compatibility is gated on
-- the server's self-reported API revision, not the marketing version.
M.MIN_API_REVISION = 7
M.COMMAND_TIMEOUT = 5000
M.LIVENESS_TIMEOUT = 250
M.AUTHORIZATION_TIMEOUT = 500
M.DISCOVERY_TIMEOUT = 5000
M.PROCESS_TIMEOUT = 1000
-- Slow TUI boots (sign-in restoration, folder trust) need more than a quick
-- poll before refusal; the wait only delays a refusal, never a delivery.
M.INPUT_READY_TIMEOUT = 15000
M.INPUT_READY_INTERVAL = 100
M.SCREEN_READY_LINES = 40
M.MAX_DUMP_LINES = 1000
M.MIN_SPLIT_PERCENT = 1
M.MAX_SPLIT_PERCENT = 99
M.FOCUS_SETTLE_MS = 50

local BLOCK_LABEL_PREFIX = "ajans:"
local BLOCK_LABEL_HASH_BYTES = 12
local TERMINAL_CREATOR = "com.superlogical.terminal"
-- Reuse must stay visible: silently attaching to an existing agent would
-- confuse users who expect a fresh start, so external paths announce it.
local AGENT_REUSE_MESSAGE = "Reusing the existing Rex agent for **%s**"
local TERMINAL_CREATE_MESSAGE =
  "Rex backend cannot embed sessions in a Neovim terminal; set `cli.mux.create` to `split` or `window`"

---@param cmd string[]
---@param opts? vim.SystemOpts
---@return vim.SystemCompleted
function M._run(cmd, opts)
  opts = vim.tbl_extend("force", { text = true }, opts or {})
  local timeout = opts.timeout or M.COMMAND_TIMEOUT
  opts.timeout = nil
  return vim.system(cmd, opts):wait(timeout)
end

---@param cmd string[]
---@param opts vim.SystemOpts
---@param callback fun(result:vim.SystemCompleted)
function M._run_async(cmd, opts, callback)
  vim.system(cmd, opts, callback)
end

---@param args string[]
---@return string[]
local function rex_cmd(args)
  local cmd = { "rex" }
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
  local message = result.stderr ~= "" and result.stderr or result.stdout
  message = type(message) == "string" and vim.trim(message) or ""
  return message ~= "" and message or "Rex command failed"
end

---@param message string
---@return boolean
local function stopped_error(message)
  message = message:lower()
  return message:find("connection refused", 1, true) ~= nil
    or message:find("failed to connect", 1, true) ~= nil
    or message:find("server is not running", 1, true) ~= nil
    or message:find("no such file", 1, true) ~= nil
    or message:find("not running", 1, true) ~= nil
end

---@class ajans.rex.ExecOpts
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
---@param opts? ajans.rex.ExecOpts
---@return vim.SystemCompleted?, string?
local function execute(args, opts)
  opts = opts or {}
  local cmd = rex_cmd(args)
  local rendered = display_command(cmd, opts.redact)
  local system_opts = vim.tbl_extend("force", { text = true }, opts.system or {})
  local ok, result = pcall(M._run, cmd, system_opts)
  if not ok then
    local message = tostring(result)
    if opts.notify ~= false then
      Util.error(("Failed to execute Rex command: `%s`\n%s"):format(rendered, message))
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
    Util.error(("Rex command failed: `%s`\n%s"):format(rendered, message))
  end
  return nil, message
end

---@param args string[]
---@param opts? ajans.rex.ExecOpts
---@return table?, string?
function M.request(args, opts)
  local result, err = execute(args, opts)
  if not result then
    return nil, err
  end
  local value = decode(result.stdout)
  if type(value) ~= "table" then
    local message = "Rex command returned malformed JSON: `"
      .. display_command(rex_cmd(args), opts and opts.redact)
      .. "`"
    if not opts or opts.notify ~= false then
      Util.error(message)
    end
    return nil, message
  end
  return value
end

---@param args string[]
---@param opts? ajans.rex.ExecOpts
---@return string?, string?
function M.command(args, opts)
  local result, err = execute(args, opts)
  return result and result.stdout or nil, err
end

---@return string?
function M.version()
  if vim.fn.executable("rex") ~= 1 then
    return
  end
  local ok, result = pcall(M._run, { "rex", "version" }, { text = true })
  if not ok or result.code ~= 0 then
    return
  end
  return result.stdout and result.stdout:match("rex (%S+)") or nil
end

---@return table?, string?
function M.server_status()
  -- whoami with autostart disabled: probing must never spawn a Rex server
  -- for users who merely left backend selection on auto.
  local value, err = M.request({ "whoami", "--autostart=false", "--json" }, { notify = false, stopped_ok = true })
  if not value then
    if err == "stopped" then
      return { running = false }
    end
    return nil, err
  end
  if type(value.endpoint) ~= "string" then
    return nil, "Rex whoami returned no server endpoint"
  end
  local version = M.request({ "api", "call", "server.version" }, { notify = false })
  return {
    running = true,
    -- Process-identity pinning reads the local process table, so only a
    -- server on a local unix socket can be driven safely; a remote Rex
    -- host must fail closed instead of guessing at foreign processes.
    local_server = value.endpoint:find("^unix://") ~= nil,
    endpoint = value.endpoint,
    instance_id = value.instance_id,
    rex_version = value.rex_version,
    api_revision = version and tonumber(version.api_revision) or nil,
  }
end

---@return boolean, string?, string?
function M.validate()
  if vim.fn.has("win32") == 1 then
    return false, "Rex backend is supported on macOS, Linux, and FreeBSD; Windows is not supported"
  end
  if vim.fn.executable("rex") ~= 1 then
    return false, "Rex backend requires the `rex` CLI, but `rex` is not installed"
  end
  local version = M.version()
  if not version then
    return false, "Unable to determine the installed Rex version from `rex version`"
  end
  return true, nil, version
end

---@return boolean
function M.is_server_running()
  local status = M.server_status()
  return status ~= nil
    and status.running == true
    and status.local_server == true
    and status.api_revision ~= nil
    and status.api_revision >= M.MIN_API_REVISION
end

---@return boolean
function M.is_usable()
  local valid = M.validate()
  if not valid then
    return false
  end
  local status = M.server_status()
  if status == nil then
    return false
  end
  if not status.running then
    -- A stopped local server is fine: the rex CLI autostarts it when a
    -- session is created, so usability must not require it to be up yet.
    return true
  end
  return status.local_server == true and status.api_revision ~= nil and status.api_revision >= M.MIN_API_REVISION
end

---@return boolean
function M.ensure_server()
  local valid, err = M.validate()
  if not valid then
    Util.error(err or "Rex is unavailable")
    return false
  end
  local status, status_err = M.server_status()
  if not status then
    Util.error(status_err or "Unable to query the Rex server")
    return false
  end
  if status.running and not status.local_server then
    Util.error(
      "Rex backend requires a local Rex server; the connected endpoint is remote: " .. tostring(status.endpoint)
    )
    return false
  end
  if status.running and (status.api_revision == nil or status.api_revision < M.MIN_API_REVISION) then
    Util.error(
      ("Rex backend requires server API revision >= %d (found %s); update Rex"):format(
        M.MIN_API_REVISION,
        tostring(status.api_revision)
      )
    )
    return false
  end
  return true
end

---@return string?, string?
local function host_ids()
  local session = vim.env.REX_SESSION
  local block = vim.env.REX_BLOCK
  if type(session) == "string" and session ~= "" and type(block) == "string" and block ~= "" then
    return session, block
  end
end

---@param self ajans.cli.muxer.Rex
---@return string[]
local function target_args(self)
  return { "-s", self.rex_session_id, "-b", self.rex_block_id }
end

---@param session_id string
---@param block_id string
---@param method string
---@param opts? ajans.rex.ExecOpts
---@return table?, string?
local function block_call(session_id, block_id, method, opts)
  return M.request({ "block", "call", "-s", session_id, "-b", block_id, method }, opts)
end

---@param self ajans.cli.muxer.Rex
---@param opts? ajans.rex.ExecOpts
---@return table?, string?
local function process_info(self, opts)
  if not self.rex_session_id or not self.rex_block_id then
    return nil, "missing Rex block identity"
  end
  return block_call(self.rex_session_id, self.rex_block_id, "process", opts)
end

function M:init()
  -- Rex sessions always live in the Rex app, never in a Neovim terminal.
  self.external = true
  self.priority = 10
end

---@return string
function M:block_label()
  return ("%s%s %s"):format(BLOCK_LABEL_PREFIX, self.tool.name, vim.fn.sha256(self.cwd):sub(1, BLOCK_LABEL_HASH_BYTES))
end

---@return string[]
function M:launch_cmd()
  local cmd = vim.deepcopy(self.tool.cmd or {})
  local env = self.tool.env or {}
  if vim.tbl_isempty(env) then
    return cmd
  end
  -- Rex terminal blocks have no per-command environment option, so the
  -- tool's configured environment is applied with env(1) in argv form,
  -- which avoids any shell quoting or parsing of the values.
  local ret = { "env" }
  for key, value in pairs(env) do
    if value == false then
      vim.list_extend(ret, { "-u", key })
    else
      ret[#ret + 1] = ("%s=%s"):format(key, tostring(value))
    end
  end
  vim.list_extend(ret, cmd)
  return ret
end

---@param value any
---@return table?
local function as_table(value)
  -- JSON null decodes to vim.NIL, which is truthy and cannot be indexed.
  return type(value) == "table" and value or nil
end

---@param session_id string
---@param block_id string
local function rollback_block(session_id, block_id)
  -- Only ever called with IDs this start created, so closing cannot touch
  -- a block the user made themselves.
  M.command({ "block", "close", "-s", session_id, block_id }, { notify = false })
end

---@param self ajans.cli.muxer.Rex
---@param session_id string
---@param block_id string
---@param window_id string?
---@return boolean
local function finish_start(self, session_id, block_id, window_id)
  local info = block_call(session_id, block_id, "process", { system = { timeout = M.PROCESS_TIMEOUT } })
  local child = info and as_table(info.child)
  local pid = child and tonumber(child.pid)
  if not pid then
    rollback_block(session_id, block_id)
    Util.error("Rex block creation response is missing a stable child process")
    return false
  end
  self.id = ("rex %s"):format(block_id)
  self.identity = block_id
  self.rex_session_id = session_id
  self.rex_block_id = block_id
  self.rex_window_id = window_id
  self.rex_pid = pid
  self.rex_label = self:block_label()
  self.mux_session = session_id
  self.started = true
  -- A just-launched TUI needs the boot-tolerant authorization wait, like
  -- Herdr's fresh launches; adopted sessions stay unfresh.
  self.fresh = true
  return true
end

---@param self ajans.cli.muxer.Rex
---@return boolean
local function adopt_owned(self)
  local states = M.sessions()
  local wanted_label = self:block_label()
  local fallback
  for _, state in ipairs(states) do
    local tool = type(state.tool) == "table" and state.tool.name or state.tool
    if tool == self.tool.name then
      -- The owned label hashes the launch-time cwd, so it stays a stable
      -- ownership key even when discovery reports a symlink-resolved cwd
      -- (for example /private/tmp for a session launched in /tmp).
      if state.rex_label == wanted_label then
        fallback = state
        break
      end
      if state.cwd == self.cwd then
        fallback = fallback or state
      end
    end
  end
  if not fallback then
    return false
  end
  self.id = fallback.id
  self.identity = fallback.identity
  self.rex_session_id = fallback.rex_session_id
  self.rex_window_id = fallback.rex_window_id
  self.rex_block_id = fallback.rex_block_id
  self.rex_pid = fallback.rex_pid
  self.rex_label = fallback.rex_label
  self.mux_session = fallback.mux_session
  self.pids = fallback.pids
  self.started = true
  return true
end

---@return integer? percent
local function split_percent()
  local size = Config.cli.mux.split.size
  local desired = size
  if size > 1 then
    local session_id, block_id = host_ids()
    local info = session_id and block_id and block_call(session_id, block_id, "size", { notify = false })
    local dimension = info and (Config.cli.mux.split.vertical and tonumber(info.columns) or tonumber(info.rows))
    if not dimension or dimension <= 0 then
      Util.error("Unable to resolve the Rex split size in cells without the anchor block size")
      return
    end
    desired = size / dimension
  end
  local percent = math.floor(desired * 100 + 0.5)
  if percent < M.MIN_SPLIT_PERCENT or percent > M.MAX_SPLIT_PERCENT then
    Util.error(
      ("Rex split size %s falls outside the supported %d%%-%d%% layout range"):format(
        tostring(size),
        M.MIN_SPLIT_PERCENT,
        M.MAX_SPLIT_PERCENT
      )
    )
    return
  end
  return percent
end

---@return string
local function focus_flag()
  return Config.cli.mux.focus and "--focus" or "--focus=false"
end

---@param self ajans.cli.muxer.Rex
---@param session_id string
---@param anchor_id string
---@return boolean
local function start_split(self, session_id, anchor_id)
  local percent = split_percent()
  if not percent then
    return false
  end
  local args = {
    "split",
    "-s",
    session_id,
    "-b",
    anchor_id,
    "--split=" .. (Config.cli.mux.split.vertical and "right" or "below"),
    "--ratio",
    tostring(percent),
    "--label",
    self:block_label(),
    "-c",
    self.cwd,
    focus_flag(),
    "--json",
    "--",
  }
  vim.list_extend(args, self:launch_cmd())
  local result = M.request(args, { redact = true })
  local block_id = result and result.block_ids and result.block_ids[1]
  if type(block_id) ~= "string" then
    Util.error("Rex split creation response is missing a stable block ID")
    return false
  end
  if not finish_start(self, session_id, block_id, nil) then
    return false
  end
  Util.info(("Started **%s** in a new Rex split"):format(self.tool.name))
  return true
end

---@param self ajans.cli.muxer.Rex
---@param session_id string
---@return boolean
local function start_window(self, session_id)
  local args = {
    "window",
    "new",
    "-s",
    session_id,
    self.tool.name,
    "-c",
    self.cwd,
    focus_flag(),
    "--json",
    "--",
  }
  vim.list_extend(args, self:launch_cmd())
  local result = M.request(args, { redact = true })
  local block_id = result and result.block_ids and result.block_ids[1]
  local window_id = result and result.window_id
  if type(block_id) ~= "string" or type(window_id) ~= "string" then
    if type(block_id) == "string" then
      rollback_block(session_id, block_id)
    end
    Util.error("Rex window creation response is missing stable block or window IDs")
    return false
  end
  -- window new labels the window, not the block; rename the block so owned
  -- agents stay recognizable (and preferred) during later discovery.
  if not M.command({ "block", "rename", "-s", session_id, block_id, self:block_label() }) then
    rollback_block(session_id, block_id)
    return false
  end
  if not finish_start(self, session_id, block_id, window_id) then
    return false
  end
  Util.info(("Started **%s** in a new Rex window"):format(self.tool.name))
  return true
end

---@param self ajans.cli.muxer.Rex
---@return boolean
local function start_session(self)
  local args = {
    "new",
    self:block_label(),
    "-c",
    self.cwd,
    "--window",
    self.tool.name,
    "--json",
    "--",
  }
  vim.list_extend(args, self:launch_cmd())
  local result = M.request(args, { redact = true })
  local session_id = result and result.session_id
  local window = result and result.initial_windows and result.initial_windows[1]
  local block_id = window and window.block_ids and window.block_ids[1]
  local window_id = window and window.window_id
  if type(session_id) ~= "string" or type(block_id) ~= "string" then
    Util.error("Rex session creation response is missing stable session or block IDs")
    return false
  end
  if not M.command({ "block", "rename", "-s", session_id, block_id, self:block_label() }) then
    rollback_block(session_id, block_id)
    return false
  end
  if not finish_start(self, session_id, block_id, type(window_id) == "string" and window_id or nil) then
    return false
  end
  Util.info(("Started **%s** in a new Rex session"):format(self.tool.name))
  return true
end

---@return ajans.cli.terminal.Cmd? cmd
---@return boolean started
function M:start()
  if Config.cli.mux.create == "terminal" then
    Util.error(TERMINAL_CREATE_MESSAGE)
    return nil, false
  end
  if not M.ensure_server() then
    return nil, false
  end
  if adopt_owned(self) then
    Util.info(AGENT_REUSE_MESSAGE:format(self.tool.name))
    return nil, true
  end
  local session_id, block_id = host_ids()
  local started ---@type boolean
  if session_id and block_id and Config.cli.mux.create == "split" then
    started = start_split(self, session_id, block_id)
  elseif session_id and Config.cli.mux.create == "window" then
    started = start_window(self, session_id)
  else
    started = start_session(self)
  end
  return nil, started
end

---@return ajans.cli.terminal.Cmd?
function M:attach() end

function M:detach() end

function M:is_running()
  return self.rex_pid ~= nil and vim.api.nvim_get_proc(self.rex_pid) ~= nil
end

---@param self ajans.cli.muxer.Rex
---@param lines integer
---@param format string
---@return string?
local function capture_tail(self, lines, format)
  if not self.rex_session_id or not self.rex_block_id then
    return
  end
  local args = { "capture", "-s", self.rex_session_id, "-b", self.rex_block_id, "--format=" .. format }
  -- Rex capture has no line limit and returns the whole scrollback; keep
  -- only the requested tail so Ajans memory stays bounded.
  local out = M.command(args, { notify = false })
  if not out then
    return
  end
  local all = vim.split(out, "\n", { plain = true })
  local first = math.max(1, #all - lines + 1)
  return table.concat(vim.list_slice(all, first), "\n")
end

--- Screen-based input readiness: a matching process is not proof the TUI can
--- receive input, and splash or trust screens silently swallow prompts.
---@param self ajans.cli.muxer.Rex
---@return boolean ready
local function screen_input_ready(self)
  local ready = self.tool.mux_ready
  if not ready or not self.rex_block_id then
    return true
  end
  local dump = capture_tail(self, M.SCREEN_READY_LINES, "text")
  if not dump then
    return false
  end
  for _, marker in ipairs(ready.blocked or {}) do
    if dump:find(marker, 1, true) then
      return false
    end
  end
  for _, marker in ipairs(ready.required or {}) do
    if not dump:find(marker, 1, true) then
      return false
    end
  end
  return true
end

---@param foreground table
---@return ajans.cli.ProcessMatch
local function foreground_proc(foreground)
  local path = foreground.path or foreground.argv0 or foreground.name or ""
  return {
    pid = tonumber(foreground.pid),
    cmd = foreground.argv0 or path,
    executable = path ~= "" and vim.fs.basename(path) or nil,
    cwd = foreground.cwd,
  }
end

--- Tell whether a process sits in the tty foreground group, tolerating
--- inventories that lack pgid by falling back to the reported pid.
---@param proc ajans.cli.Proc
---@param foreground_group_id number
---@param foreground_pid number
---@return boolean
local function in_foreground_group(proc, foreground_group_id, foreground_pid)
  local in_group = (proc.pgid ~= nil and proc.pgid == foreground_group_id)
    or (proc.pgid == nil and proc.pid == foreground_pid)
  return in_group and (not proc.tpgid or proc.tpgid <= 0 or proc.tpgid == proc.pgid)
end

--- Tell whether a process is exactly the one already authorized for input, so
--- the walk can stop instead of settling for a first-match fallback.
---@param self ajans.cli.muxer.Rex
---@param proc ajans.cli.Proc
---@param identity table
---@return boolean
local function is_authorized_process(self, proc, identity)
  if self._authorized_process then
    return Procs.same_identity(self._authorized_process, identity)
  end
  return self._authorized_pid == proc.pid
end

--- Find the tool among the child's foreground-group members. An already
--- authorized process wins; otherwise the first match is used so a fresh
--- session can be authorized once.
---@param self ajans.cli.muxer.Rex
---@param procs ajans.cli.Procs
---@param child_pid number
---@param foreground_group_id number
---@param foreground_pid number
---@return number? matched_pid
---@return table? matched_process
local function find_foreground_tool(self, procs, child_pid, foreground_group_id, foreground_pid)
  local matched_pid
  local matched_process
  procs:walk(child_pid, function(proc)
    if not in_foreground_group(proc, foreground_group_id, foreground_pid) or not self.tool:is_proc(proc) then
      return nil
    end
    local identity = Procs.identity(proc)
    if is_authorized_process(self, proc, identity) then
      matched_pid = proc.pid
      matched_process = identity
      return true
    end
    if not self._authorized_pid then
      matched_pid = matched_pid or proc.pid
      matched_process = matched_process or identity
    end
  end)
  return matched_pid, matched_process
end

--- Trust the server-reported foreground when the local process inventory is
--- incomplete, because ps can miss a just-started tool.
---@param self ajans.cli.muxer.Rex
---@param foreground table
---@param foreground_pid number
---@return number? matched_pid
---@return table? matched_process
local function match_reported_foreground(self, foreground, foreground_pid)
  if not self.tool:is_proc(foreground_proc(foreground)) then
    return nil
  end
  local identity = { pid = foreground_pid, runtime_executable = foreground.path }
  local same = self._authorized_process and Procs.same_identity(self._authorized_process, identity)
  if same or not self._authorized_pid or self._authorized_pid == foreground_pid then
    return foreground_pid, identity
  end
end

--- Extract the reported child and foreground pids, accepting only a report
--- that belongs to this session's own Rex block.
---@param self ajans.cli.muxer.Rex
---@param info table?
---@return number? child_pid
---@return table? foreground
---@return number? foreground_pid
local function reported_pids(self, info)
  local child = info and as_table(info.child)
  local child_pid = child and tonumber(child.pid)
  local foreground = info and as_table(info.foreground)
  local foreground_pid = foreground and tonumber(foreground.pid)
  if not child_pid or child_pid ~= self.rex_pid or not foreground_pid then
    return nil
  end
  return child_pid, foreground, foreground_pid
end

--- Rex reports the tty foreground process-group leader, which is the
--- launching shell when the tool runs in the shell's own group, so the
--- tool is matched among the leader's foreground-group members rather
--- than by equality with the reported pid.
---@param procs ajans.cli.Procs
---@param foreground_pid number
---@return number
local function foreground_group_of(procs, foreground_pid)
  local leader = procs:get(foreground_pid)
  return leader and (leader.tpgid or leader.pgid) or foreground_pid
end

--- Authorize automated input only for the tool still in this block's
--- foreground group, so keystrokes never reach a process the user started later.
---@param self ajans.cli.muxer.Rex
---@param info table?
---@param procs ajans.cli.Procs
---@return boolean
local function accepts_process(self, info, procs)
  local child_pid, foreground, foreground_pid = reported_pids(self, info)
  if not child_pid or not foreground_pid then
    return false
  end
  local foreground_group_id = foreground_group_of(procs, foreground_pid)
  local matched_pid, matched_process = find_foreground_tool(self, procs, child_pid, foreground_group_id, foreground_pid)
  if not matched_pid and foreground and not procs:is_complete() then
    matched_pid, matched_process = match_reported_foreground(self, foreground, foreground_pid)
  end
  -- A changed or not-yet-ready tool must not keep input authorization.
  if self._authorized_pid and matched_pid ~= self._authorized_pid then
    return false
  end
  if matched_pid and not screen_input_ready(self) then
    return false
  end
  self._authorized_pid = matched_pid
  self._authorized_process = matched_process
  return matched_pid ~= nil
end

function M:accepts_automated_input()
  if not self.rex_pid or type(self.tool.is_proc) ~= "function" then
    return false
  end
  local info = process_info(self, { notify = false, system = { timeout = M.AUTHORIZATION_TIMEOUT } })
  return accepts_process(self, info, Procs.new({ timeout = M.AUTHORIZATION_TIMEOUT }))
end

---@param callback fun(accepted:boolean)
function M:authorize_automated_input(callback)
  if not self.fresh then
    callback(self:accepts_automated_input())
    return
  end

  local deadline = vim.uv.now() + M.INPUT_READY_TIMEOUT
  local function check()
    local ok, accepted = pcall(self.accepts_automated_input, self)
    if not ok then
      self.fresh = false
      Util.error("Unable to authorize fresh Rex input: " .. tostring(accepted))
      callback(false)
    elseif accepted then
      self.fresh = false
      callback(true)
    elseif vim.uv.now() >= deadline then
      self.fresh = false
      callback(false)
    else
      vim.defer_fn(check, M.INPUT_READY_INTERVAL)
    end
  end
  check()
end

--- Build the session state for a tool found inside a Rex terminal block.
---@param tool ajans.cli.Tool
---@param session_id string
---@param block table
---@param child_pid number
---@param cwd string
---@return ajans.cli.session.RexState
local function block_state(tool, session_id, block, child_pid, cwd)
  return {
    id = ("rex %s"):format(block.block_id),
    identity = block.block_id,
    cwd = cwd,
    tool = tool,
    rex_session_id = session_id,
    rex_window_id = block.window_id,
    rex_block_id = block.block_id,
    rex_pid = child_pid,
    rex_label = block.label,
    mux_session = session_id,
    pids = Procs.pids(child_pid),
  }
end

--- Collect the first known tool running under a block's shell. Stops at the
--- first tool match so one block yields at most one session.
---@param ret ajans.cli.session.RexState[]
---@param tools table<string, ajans.cli.Tool>
---@param procs ajans.cli.Procs
---@param session_id string
---@param block table
---@param info table
---@param child_pid number
local function collect_block_sessions(ret, tools, procs, session_id, block, info, child_pid)
  local foreground = as_table(info.foreground)
  procs:walk(child_pid, function(proc)
    for _, tool in pairs(tools) do
      if tool:is_proc(proc) then
        local cwd = proc.cwd or (foreground and foreground.cwd)
        if cwd then
          ret[#ret + 1] = block_state(tool, session_id, block, child_pid, cwd)
        end
        return true
      end
    end
  end)
end

--- Inspect one terminal block. Returns false when the process lookup failed so
--- the caller can mark discovery as non-authoritative.
---@param ret ajans.cli.session.RexState[]
---@param tools table<string, ajans.cli.Tool>
---@param procs ajans.cli.Procs
---@param session_id string
---@param block table
---@return boolean complete
local function scan_block(ret, tools, procs, session_id, block)
  local info = block_call(session_id, block.block_id, "process", {
    notify = false,
    system = { timeout = M.PROCESS_TIMEOUT },
  })
  local child = info and as_table(info.child)
  local child_pid = child and tonumber(child.pid)
  if not info or not child_pid then
    return false
  end
  -- Blocks whose command already exited cannot host a live tool.
  if info.last_exit == nil or info.last_exit == vim.NIL then
    collect_block_sessions(ret, tools, procs, session_id, block, info, child_pid)
  end
  return true
end

--- Scan every block of one Rex session until the shared deadline passes.
---@param ret ajans.cli.session.RexState[]
---@param tools table<string, ajans.cli.Tool>
---@param procs ajans.cli.Procs
---@param session_id any Raw id from Rex JSON; checked before use.
---@param deadline number vim.uv.now() value after which the scan stops.
---@return boolean complete
local function scan_session(ret, tools, procs, session_id, deadline)
  local blocks = type(session_id) == "string"
    and M.request({ "block", "ls", "-s", session_id, "--json" }, { notify = false })
  if not blocks or type(blocks.blocks) ~= "table" then
    return false
  end
  local complete = true
  for _, block in ipairs(blocks.blocks) do
    if vim.uv.now() >= deadline then
      return false
    end
    if block.creator_name == TERMINAL_CREATOR and type(block.block_id) == "string" then
      complete = scan_block(ret, tools, procs, session_id, block) and complete
    end
  end
  return complete
end

---@return ajans.cli.session.RexState[], boolean
function M.sessions()
  local ret = {} ---@type ajans.cli.session.RexState[]
  local listing = M.request({ "ls", "--autostart=false", "--json" }, { notify = false, stopped_ok = true })
  if not listing or type(listing.sessions) ~= "table" then
    return ret, false
  end

  local tools = Config.tools()
  local procs = Procs.new()
  local complete = true
  local deadline = vim.uv.now() + M.DISCOVERY_TIMEOUT

  for _, session in ipairs(listing.sessions) do
    complete = scan_session(ret, tools, procs, session.session_id, deadline) and complete
  end

  local procs_complete = not procs.is_complete or procs:is_complete()
  return ret, complete and procs_complete
end

---@param self ajans.cli.muxer.Rex
---@param operation ajans.rex.InputOperation
---@return boolean
local function run_operation(self, operation)
  if operation.kind == "submit" then
    local args = { "send-key" }
    vim.list_extend(args, target_args(self))
    args[#args + 1] = "enter"
    return M.command(args) ~= nil
  end
  local args = { "send" }
  vim.list_extend(args, target_args(self))
  -- Prompt text travels on stdin, never in argv where any local process
  -- could read it from the rex command line.
  return M.command(args, { system = { stdin = operation.text } }) ~= nil
end

---@param self ajans.cli.muxer.Rex
local function drain_input(self)
  if self._sending then
    return
  end
  self._input_queue = self._input_queue or {}
  local operation = table.remove(self._input_queue, 1) ---@type ajans.rex.InputOperation?
  if not operation then
    return
  end
  if not self.rex_block_id or (self._authorized_pid and not self:accepts_automated_input()) then
    operation.ok = false
    self._last_send_ok = false
    self._input_queue = {}
    return
  end
  self._sending = true

  local function complete(ok)
    operation.ok = ok
    if operation.kind == "text" then
      self._last_send_ok = ok
    end
    if not ok then
      self._last_send_ok = false
      self._input_queue = {}
    end
    self._sending = false
    drain_input(self)
  end

  if operation.kind == "submit" then
    if self._last_send_ok == false then
      self._last_send_ok = nil
      complete(false)
      return
    end
    self._last_send_ok = nil
    complete(run_operation(self, operation))
    return
  end

  local function send_text()
    if self._authorized_pid and not self:accepts_automated_input() then
      complete(false)
      return
    end
    complete(run_operation(self, operation))
  end
  if self.tool.mux_focus then
    local args = { "send" }
    vim.list_extend(args, target_args(self))
    if M.command(args, { system = { stdin = "\27[I" } }) == nil then
      complete(false)
      return
    end
    vim.defer_fn(send_text, M.FOCUS_SETTLE_MS)
  else
    send_text()
  end
end

---@param text string
---@return boolean?
function M:send(text)
  if not self.rex_session_id or not self.rex_block_id then
    return false
  end
  self._input_queue = self._input_queue or {}
  local operation = { kind = "text", text = text } ---@type ajans.rex.TextOperation
  self._input_queue[#self._input_queue + 1] = operation
  drain_input(self)
  return operation.ok
end

---@return boolean?
function M:submit()
  if not self.rex_session_id or not self.rex_block_id then
    return false
  end
  self._input_queue = self._input_queue or {}
  local operation = { kind = "submit" } ---@type ajans.rex.SubmitOperation
  self._input_queue[#self._input_queue + 1] = operation
  drain_input(self)
  return operation.ok
end

---@return string?
function M:dump()
  if not self.rex_block_id then
    return
  end
  local lines = math.max(1, math.min(M.MAX_DUMP_LINES, math.floor(Config.cli.mux.dump)))
  return capture_tail(self, lines, "vt")
end

return M
