local Config = require("ajans.config")
local Util = require("ajans.util")

local M = {}

M.backends = {} ---@type table<string,ajans.cli.Session>
M.did_setup = false
M.backend = nil ---@type string?
M._attached = {} ---@type table<string,ajans.cli.Session>
M._attachment_generation = 0

---@class ajans.cli.session.State
---@field id string unique id of the running tool (typically pid of tool)
---@field identity? string stable backend resource identity
---@field cwd string
---@field tool ajans.cli.Tool|string
---@field backend? string
---@field pids? integer[] list of pids associated with this session
---@field started? boolean
---@field external? boolean external sessions won't be opened in a terminal
---@field parent? ajans.cli.Session
---@field mux_session? string
---@field mux_backend? string
---@field mux_identity? string stable identity of the wrapped backend session
---@field herdr_terminal_id? string
---@field herdr_pane_id? string
---@field herdr_workspace_id? string
---@field herdr_tab_id? string
---@field herdr_agent? boolean
---@field herdr_name? string
---@field herdr_label? string
---@field herdr_agent_session? any
---@field herdr_placement? "workspace"|"tab"|"split"
---@field rex_session_id? string
---@field rex_window_id? string
---@field rex_block_id? string
---@field rex_pid? number
---@field rex_label? string

---@class ajans.cli.session.CreateOpts
---@field tool ajans.cli.Tool|string
---@field id? string
---@field identity? string
---@field cwd? string
---@field pids? integer[]
---@field started? boolean
---@field external? boolean
---@field parent? ajans.cli.Session
---@field mux_session? string
---@field mux_backend? string
---@field mux_identity? string
---@field herdr_terminal_id? string
---@field herdr_pane_id? string
---@field herdr_workspace_id? string
---@field herdr_tab_id? string
---@field herdr_agent? boolean
---@field herdr_name? string
---@field herdr_label? string
---@field herdr_agent_session? any
---@field herdr_placement? "workspace"|"tab"|"split"
---@field rex_session_id? string
---@field rex_window_id? string
---@field rex_block_id? string
---@field rex_pid? number
---@field rex_label? string
---@field fresh? boolean

---@alias ajans.cli.session.Opts ajans.cli.session.State|ajans.cli.session.CreateOpts

---@class ajans.cli.Session: ajans.cli.session.State
---@field sid string unique id based on tool and cwd
---@field tool ajans.cli.Tool
---@field backend string
---@field fresh? boolean
---@field _authorized_pid? integer
---@field _authorized_process? ajans.cli.ProcessIdentity
---@field _sending? boolean
---@field _last_send_ok? boolean
---@field priority integer
---@field dump? fun(self:ajans.cli.Session):string?
local B = {}
B.__index = B
B.priority = 0

--- Send text to the session
---@param _ string
function B:send(_)
  error("Backend:send() not implemented")
end

--- Initialize the session backend (optional hook)
function B:init() end

--- Submit the current input to the session
function B:submit()
  error("Backend:submit() not implemented")
end

--- Attach to an existing session
--- If the backend returns a Cmd, a new terminal session will be spawned
---@return ajans.cli.terminal.Cmd?
---@return boolean? accepted
function B:attach() end

--- Detach from an existing session
function B:detach() end

--- Start a new session.
--- The boolean reports creation success; a command requests a terminal wrapper.
---@return ajans.cli.terminal.Cmd? cmd
---@return boolean started
function B:start()
  error("Backend:start() not implemented")
end

--- Check if the session is still running
---@return boolean
function B:is_running()
  error("Backend:is_running() not implemented")
end

--- Confirm automated input still targets the expected tool.
---@return boolean
function B:accepts_automated_input()
  return self:is_running()
end

---@param callback fun(accepted:boolean)
function B:authorize_automated_input(callback)
  callback(self:accepts_automated_input())
end

function B:is_attached()
  if M._attached[self.id] ~= nil then
    return true
  end
  local identity = self.mux_identity or self.identity
  if identity then
    for _, session in pairs(M._attached) do
      if (session.mux_identity or session.identity) == identity then
        return true
      end
    end
  end
  return false
end

--- List active sessions and whether absence is authoritative.
--- Transient scans return false so known sessions remain attached.
---@return ajans.cli.session.State[] sessions
---@return boolean authoritative
function B.sessions()
  error("Backend:sessions() not implemented")
end

---@class ajans.cli.session.ResolveOpts
---@field configured? "auto"|"tmux"|"herdr"|"rex"
---@field herdr_host? boolean
---@field tmux_host? boolean
---@field rex_host? boolean
---@field installed? {tmux:boolean,herdr:boolean,rex:boolean}
---@field herdr_running? boolean
---@field herdr_usable? boolean
---@field rex_running? boolean
---@field rex_usable? boolean

--- Backend modules that expose usability and server probes, keyed by backend.
local PROBED_BACKEND_MODULES = {
  herdr = "ajans.cli.session.herdr",
  rex = "ajans.cli.session.rex",
}

--- Backends that a config value may select explicitly, bypassing detection.
local EXPLICIT_BACKENDS = { tmux = true, herdr = true, rex = true }

--- Fallback when no backend qualifies, kept for compatibility with tmux-only
--- setups.
local DEFAULT_BACKEND = "tmux"

---@class ajans.cli.session.ResolveCtx
---@field opts ajans.cli.session.ResolveOpts
---@field installed {tmux:boolean,herdr:boolean,rex:boolean}
---@field herdr_host boolean
---@field tmux_host boolean
---@field rex_host boolean
---@field usable table<string, boolean> Memoized so a probe subprocess runs once.

--- Detect installed backends lazily so tests can inject a fixed set.
---@param opts ajans.cli.session.ResolveOpts
---@return {tmux:boolean,herdr:boolean,rex:boolean}
local function detect_installed(opts)
  return opts.installed
    or {
      tmux = vim.fn.executable("tmux") == 1,
      herdr = vim.fn.executable("herdr") == 1,
      rex = vim.fn.executable("rex") == 1,
    }
end

--- Resolve which multiplexer hosts the current Neovim, honoring overrides.
---@param opts ajans.cli.session.ResolveOpts
---@return boolean herdr_host
---@return boolean tmux_host
---@return boolean rex_host
local function detect_hosts(opts)
  local herdr_host = opts.herdr_host
  if herdr_host == nil then
    herdr_host = vim.env.HERDR_ENV == "1"
  end
  local tmux_host = opts.tmux_host
  if tmux_host == nil then
    tmux_host = vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
  end
  local rex_host = opts.rex_host
  if rex_host == nil then
    rex_host = vim.env.REX_SESSION ~= nil
      and vim.env.REX_SESSION ~= ""
      and vim.env.REX_BLOCK ~= nil
      and vim.env.REX_BLOCK ~= ""
  end
  return herdr_host, tmux_host, rex_host
end

--- Decide whether a probed backend can be used, spawning its probe only when
--- no override or injected install set makes the answer known.
---@param ctx ajans.cli.session.ResolveCtx
---@param name "herdr"|"rex"
---@return boolean
local function backend_usable(ctx, name)
  local cached = ctx.usable[name]
  if cached ~= nil then
    return cached
  end
  local opts = ctx.opts
  local usable = opts[name .. "_usable"]
  if usable == nil then
    if opts.installed or opts[name .. "_running"] ~= nil then
      usable = ctx.installed[name]
    else
      usable = ctx.installed[name] and require(PROBED_BACKEND_MODULES[name]).is_usable() or false
    end
  end
  ctx.usable[name] = usable
  return usable
end

--- Decide whether a usable backend's server is running; unusable backends are
--- never probed so they cannot spawn a subprocess.
---@param ctx ajans.cli.session.ResolveCtx
---@param name "herdr"|"rex"
---@return boolean
local function backend_running(ctx, name)
  local running = ctx.opts[name .. "_running"]
  if running ~= nil then
    return running
  end
  return backend_usable(ctx, name) and require(PROBED_BACKEND_MODULES[name]).is_server_running() or false
end

--- Pick the sole installed backend when nothing else qualified, so health can
--- report that backend's actionable error instead of a silent tmux fallback.
---@param ctx ajans.cli.session.ResolveCtx
---@return "herdr"|"rex"|nil
local function sole_installed_backend(ctx)
  local installed = ctx.installed
  if installed.herdr and not installed.tmux then
    return "herdr"
  end
  if installed.rex and not installed.tmux and not installed.herdr then
    return "rex"
  end
end

--- A plain tmux host wins before any backend subprocess runs. Nested Herdr
--- hosts still retain the documented higher precedence.
---@param ctx ajans.cli.session.ResolveCtx
---@return "tmux"|"herdr"|"rex"|nil
local function plain_tmux_host(ctx)
  if ctx.tmux_host and not ctx.herdr_host and ctx.installed.tmux then
    return "tmux"
  end
end

---@param ctx ajans.cli.session.ResolveCtx
---@return "tmux"|"herdr"|"rex"|nil
local function herdr_host_backend(ctx)
  -- Probe before testing the host flag so the probe order stays stable.
  local usable = backend_usable(ctx, "herdr")
  if ctx.herdr_host and usable then
    return "herdr"
  end
end

---@param ctx ajans.cli.session.ResolveCtx
---@return "tmux"|"herdr"|"rex"|nil
local function tmux_host_backend(ctx)
  if ctx.tmux_host and ctx.installed.tmux then
    return "tmux"
  end
end

---@param ctx ajans.cli.session.ResolveCtx
---@return "tmux"|"herdr"|"rex"|nil
local function rex_host_backend(ctx)
  local usable = backend_usable(ctx, "rex")
  if ctx.rex_host and usable then
    return "rex"
  end
end

--- Build a stage that selects a backend whose server is already running.
---@param name "herdr"|"rex"
---@return fun(ctx:ajans.cli.session.ResolveCtx):string?
local function running_backend(name)
  return function(ctx)
    if backend_usable(ctx, name) and backend_running(ctx, name) then
      return name
    end
  end
end

--- Detection stages in documented precedence order; the first hit wins.
local RESOLVE_STAGES = {
  plain_tmux_host,
  herdr_host_backend,
  tmux_host_backend,
  rex_host_backend,
  running_backend("herdr"),
  running_backend("rex"),
  sole_installed_backend,
}

---@param opts? ajans.cli.session.ResolveOpts
---@return "tmux"|"herdr"|"rex"
function M.resolve_backend(opts)
  opts = opts or {}
  local configured = opts.configured or Config.cli.mux.backend or "auto"
  if EXPLICIT_BACKENDS[configured] then
    return configured --[[@as "tmux"|"herdr"|"rex"]]
  end

  local herdr_host, tmux_host, rex_host = detect_hosts(opts)
  ---@type ajans.cli.session.ResolveCtx
  local ctx = {
    opts = opts,
    installed = detect_installed(opts),
    herdr_host = herdr_host,
    tmux_host = tmux_host,
    rex_host = rex_host,
    usable = {},
  }
  for _, stage in ipairs(RESOLVE_STAGES) do
    local backend = stage(ctx)
    if backend then
      return backend
    end
  end
  return DEFAULT_BACKEND
end

---@param state ajans.cli.session.Opts
function M.new(state)
  M.setup()
  local tool = state.tool
  tool = type(tool) == "string" and Config.get_tool(tool) or tool --[[@as ajans.cli.Tool]]
  local backend = M.selected_backend()
  local super = assert(M.backends[backend], "unknown backend: " .. backend)
  local meta = getmetatable(state)
  local self = setmetatable(state, super) --[[@as ajans.cli.Session]]
  self.tool = tool
  self.cwd = M.cwd(state)
  self.backend = backend
  self.sid = M.sid({ tool = tool.name, cwd = self.cwd })
  self.id = self.id or self.sid
  if meta ~= super and self.init then
    self:init()
  end
  return self
end

---@param opts? {cwd?:string}
function M.cwd(opts)
  return vim.fs.normalize(vim.fn.fnamemodify(opts and opts.cwd or vim.fn.getcwd(0), ":p"))
end

---@param opts {tool:string, cwd?:string}
function M.sid(opts)
  local tool = assert(opts and opts.tool, "missing tool")
  local cwd = M.cwd(opts)
  return ("%s %s"):format(tool, vim.fn.sha256(cwd):sub(1, 16 - #tool))
end

---@param name string
---@param backend ajans.cli.Session
function M.register(name, backend)
  if name ~= "tmux" and name ~= "herdr" and name ~= "rex" then
    return
  end
  setmetatable(backend, B)
  backend.__index = backend
  backend.backend = name
  M.backends[name] = backend
end

function M.setup()
  if M.did_setup then
    return
  end
  M.did_setup = true
  Config.tools()
  M.register("tmux", require("ajans.cli.session.tmux"))
  M.register("herdr", require("ajans.cli.session.herdr"))
  M.register("rex", require("ajans.cli.session.rex"))
  M.backend = M.resolve_backend()
end

---@return string
function M.selected_backend()
  M.setup()
  M.backend = M.backend or M.resolve_backend()
  return M.backend
end

---@param left ajans.cli.Session
---@param right ajans.cli.Session
---@return boolean
local function same_target(left, right)
  local left_tool = type(left.tool) == "table" and left.tool.name or left.tool
  local right_tool = type(right.tool) == "table" and right.tool.name or right.tool
  return left_tool == right_tool
    and (left.mux_identity or left.identity) == (right.mux_identity or right.identity)
    and (not left.herdr_name or left.herdr_name == right.herdr_name)
    and (not left.herdr_label or left.herdr_label == right.herdr_label)
    and (not left.herdr_agent_session or vim.deep_equal(left.herdr_agent_session, right.herdr_agent_session))
end

function M.sessions()
  M.setup()
  local ret = {} ---@type ajans.cli.Session[]
  local ids = {} ---@type table<string,boolean>
  local identities = {} ---@type table<string,ajans.cli.Session>
  local name = M.selected_backend()
  local backend = assert(M.backends[name], "unknown backend: " .. name)
  local states, authoritative = backend:sessions()
  for _, state in pairs(states) do
    state.backend = name
    state.started = true
    if ids[state.id] then
      Util.error("duplicate session id: " .. state.id)
    else
      local session = M.new(state)
      ret[#ret + 1] = session
      ids[state.id] = true
      if session.identity then
        identities[session.identity] = session
      end
      local attached = M._attached[state.id]
      if attached then
        if same_target(attached, session) then
          session._authorized_pid = attached._authorized_pid
          session._authorized_process = attached._authorized_process
          session.fresh = attached.fresh
          M._attached[state.id] = session
          M._attachment_generation = M._attachment_generation + 1
        else
          M.detach(attached)
        end
      end
    end
  end

  local function parent_for(session)
    if session.mux_identity and identities[session.mux_identity] then
      local candidate = identities[session.mux_identity]
      return same_target(session, candidate) and candidate or nil
    end
    for _, candidate in ipairs(ret) do
      if
        candidate.backend == name
        and same_target(session, candidate)
        and not vim.tbl_isempty(session.pids or {})
        and Util.overlaps(candidate.pids or {}, session.pids or {})
      then
        return candidate
      end
    end
  end

  for id, session in pairs(M._attached) do
    if not ids[id] then
      local terminal = session.backend == "terminal" and session.mux_backend == name
      local parent = terminal and parent_for(session) or nil
      local retained = authoritative == false and (terminal or session.backend == name)
      if (parent or retained) and session:is_running() then
        if parent and session.parent and same_target(session.parent, parent) then
          parent._authorized_pid = session.parent._authorized_pid
          parent._authorized_process = session.parent._authorized_process
          parent.fresh = session.parent.fresh
        end
        session.parent = parent or session.parent
        ret[#ret + 1] = session
        ids[id] = true
      end
    end
  end
  if authoritative ~= false then
    for id in pairs(M._attached) do
      if not ids[id] then
        M.detach(M._attached[id])
      end
    end
  end
  return ret
end

---@param session ajans.cli.Session
function M.detach(session)
  if M._attached[session.id] then
    M._attached[session.id] = nil
    M._attachment_generation = M._attachment_generation + 1
    session:detach()
    vim.schedule(function()
      Util.emit("AjansCliDetach", { id = session.id })
    end)
  end
  return session
end

---@param session ajans.cli.Session
function M.attach(session)
  if M._attached[session.id] then
    return session
  end
  local parent = session
  ---@type ajans.cli.terminal.Cmd?
  local cmd
  local started = session.started == true
  local fresh = not started
  if started then
    local accepted
    cmd, accepted = session:attach()
    if accepted == false then
      return session
    end
  else
    cmd, started = session:start()
  end
  if not started then
    return session
  end
  if cmd then
    local terminal_tool = session.tool:clone({ cmd = cmd.cmd })
    terminal_tool.config = vim.deepcopy(terminal_tool.config or {})
    terminal_tool.config.env = {}
    terminal_tool.env = cmd.env or {}
    local terminal = require("ajans.cli.terminal").new({
      tool = terminal_tool,
      cwd = session.cwd,
      id = "terminal: " .. (session.identity or session.sid),
      mux_backend = session.backend,
      mux_session = session.mux_session,
      mux_identity = session.identity,
      external = session.external,
      herdr_name = session.herdr_name,
      herdr_label = session.herdr_label,
      herdr_agent_session = session.herdr_agent_session,
      fresh = fresh,
      parent = session,
    })
    terminal:start()
    if not terminal.started then
      return parent
    end
    session = terminal
  end
  M._attached[session.id] = session
  M._attachment_generation = M._attachment_generation + 1
  vim.schedule(function()
    Util.emit("AjansCliAttach", { id = session.id })
  end)
  return session
end

---@param session ajans.cli.Session
---@return boolean
function M.owns(session)
  return M._attached[session.id] == session
end

function M.attached_snapshot()
  return M._attached
end

function M.attached()
  local ret = {} ---@type table<string,ajans.cli.Session>
  for id, session in pairs(M._attached) do
    if session:is_running() then
      ret[id] = session
    else
      M.detach(session)
    end
  end
  return ret
end

---@param callback fun(sessions:table<string,ajans.cli.Session>)
function M.attached_async(callback)
  local ret = {} ---@type table<string,ajans.cli.Session>
  local entries = {}
  for id, session in pairs(M._attached) do
    entries[#entries + 1] = { id = id, session = session }
  end
  local pending = #entries
  if pending == 0 then
    callback(ret)
    return
  end
  for _, entry in ipairs(entries) do
    local id, session = entry.id, entry.session
    local function complete(running)
      if M._attached[id] == session then
        if running then
          ret[id] = session
        else
          M.detach(session)
        end
      end
      pending = pending - 1
      if pending == 0 then
        callback(ret)
      end
    end
    if session.is_running_async then
      session:is_running_async(complete)
    else
      complete(session:is_running())
    end
  end
end

return M
