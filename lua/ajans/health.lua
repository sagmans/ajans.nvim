local Client = require("ajans.cli.session.herdr.client")

local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

---@param display string
local function check_process_tools(display)
  local linux = vim.fn.has("linux") == 1
  if vim.fn.executable("ps") == 1 then
    ok("`ps` is installed")
  elseif linux then
    ok("`ps` is not installed; using `/proc` for process discovery")
  else
    warn(("`ps` is not installed; %s process discovery is unavailable"):format(display))
  end
  if not linux then
    if vim.fn.executable("lsof") == 1 then
      ok("`lsof` is installed")
    else
      warn(("`lsof` is not installed; %s working-directory detection is unavailable"):format(display))
    end
  end
end

--- Report each installed, Herdr-registered tool's integration state. Only
--- tools that are configured and installed are listed; missing binaries have
--- their own report in the tools section.
---@param Herdr table
local function check_herdr_integrations(Herdr)
  local Integrations = require("ajans.cli.session.herdr.integrations")
  local tools = require("ajans.config").tools()
  local tool_names = vim.tbl_keys(tools) ---@type string[]
  table.sort(tool_names)
  for _, name in ipairs(tool_names) do
    local tool = tools[name]
    if
      Integrations.integration_for(name)
      and type(tool.cmd) == "table"
      and #tool.cmd > 0
      and vim.fn.executable(tool.cmd[1]) == 1
    then
      local assessment = Integrations.assess(name, Herdr._run)
      if not assessment or assessment.state == Integrations.STATE_CURRENT then
        ok(("`%s` Herdr integration is current"):format(name))
      elseif assessment.query_error then
        warn(("Unable to query the `%s` Herdr integration: %s"):format(name, assessment.query_error))
      else
        warn(Integrations.message(assessment))
      end
    end
  end
end

--- Report a running Herdr server's API socket and integrations, warning when
--- a restart would pick up a newer compatible version.
---@param Herdr table
---@param status table
local function check_herdr_running(Herdr, status)
  if status.restart_needed == true then
    warn(
      "The running Herdr server uses a different compatible version; restart when convenient. " .. Herdr.RESTART_WARNING
    )
  end
  local socket, socket_err = Client.trusted_socket(status)
  if socket then
    ok("The selected Herdr server is running with a trusted local API socket")
  else
    error("The selected Herdr server API socket is unusable: " .. (socket_err or "unknown error"))
  end
  check_herdr_integrations(Herdr)
end

--- Report the selected Herdr backend's availability and server state.
local function check_herdr()
  local Herdr = require("ajans.cli.session.herdr")
  local valid, message, version = Herdr.validate()
  if not valid then
    error(message or "Selected terminal multiplexer `herdr` is unavailable")
    return
  end
  ok(("Selected terminal multiplexer `herdr` %s is available"):format(version or "unknown"))
  local status, status_err = Herdr.server_status()
  if not status then
    error("Unable to query the selected Herdr server: " .. (status_err or "unknown error"))
  elseif status.running and status.compatible == false then
    error(
      "The running Herdr server is incompatible with the installed client; restart the Herdr server. "
        .. Herdr.RESTART_WARNING
    )
  elseif status.running then
    check_herdr_running(Herdr, status)
  else
    ok("The selected Herdr server is stopped and will start when Ajans creates a session")
  end
end

--- Report a running Rex server's locality and API revision, because Ajans can
--- only drive a local server that implements the required API.
---@param Rex table
---@param status table
local function check_rex_running(Rex, status)
  if not status.local_server then
    error("The selected Rex server is remote; Ajans can only drive a local Rex server: " .. tostring(status.endpoint))
  elseif status.api_revision == nil or status.api_revision < Rex.MIN_API_REVISION then
    error(
      ("The running Rex server reports API revision %s; Ajans requires >= %d; update Rex"):format(
        tostring(status.api_revision),
        Rex.MIN_API_REVISION
      )
    )
  else
    ok("The selected local Rex server is running")
  end
end

--- Report the selected Rex backend's availability and server state.
local function check_rex()
  local Rex = require("ajans.cli.session.rex")
  local valid, message, version = Rex.validate()
  if not valid then
    error(message or "Selected terminal multiplexer `rex` is unavailable")
    return
  end
  ok(("Selected terminal multiplexer `rex` %s is available"):format(version or "unknown"))
  local status, status_err = Rex.server_status()
  if not status then
    error("Unable to query the selected Rex server: " .. (status_err or "unknown error"))
  elseif status.running then
    check_rex_running(Rex, status)
  else
    ok("The selected Rex server is stopped and will start when Ajans creates a session")
  end
end

--- Report the tmux backend, which only needs its binary.
local function check_tmux()
  if vim.fn.executable("tmux") == 1 then
    ok("Selected terminal multiplexer `tmux` is installed")
  else
    error("Selected terminal multiplexer `tmux` is not installed")
  end
end

--- Backend checks keyed by selected backend; tmux is the fallback.
local BACKEND_CHECKS = {
  herdr = check_herdr,
  rex = check_rex,
}

--- Display names for backends whose process discovery needs `ps`/`lsof`.
local PROCESS_TOOL_DISPLAY = {
  tmux = "tmux",
  rex = "Rex",
}

--- Report the selected backend and the process tools its discovery relies on.
local function check_backend()
  local backend = require("ajans.cli.session").selected_backend();
  (BACKEND_CHECKS[backend] or check_tmux)()

  local display = PROCESS_TOOL_DISPLAY[backend]
  if display and vim.fn.has("win32") == 0 then
    check_process_tools(display)
  end
end

--- Report whether each configured AI CLI tool's binary is installed.
local function check_tools()
  local tools = require("ajans.config").tools()
  local tool_names = vim.tbl_keys(tools) ---@type string[]
  table.sort(tool_names)
  for _, name in ipairs(tool_names) do
    local tool = tools[name]
    local tool_name = tool.name or name
    if tool.cmd and #tool.cmd > 0 and vim.fn.executable(tool.cmd[1]) == 1 then
      ok("`" .. tool_name .. "` is installed")
    else
      warn("`" .. tool_name .. "` is not installed")
    end
  end
end

function M.check()
  start("Ajans")

  if vim.fn.has("nvim-0.11.2") == 1 then
    ok("Using Neovim >= 0.11.2")
  else
    error("Neovim >= 0.11.2 is required")
    return
  end

  start("Ajans AI CLI")
  if vim.o.autoread then
    ok("autoread is enabled")
  else
    warn("autoread is disabled, file changes from AI CLI tools will not be detected automatically")
  end

  check_backend()

  start("Ajans AI CLI Tools")
  check_tools()
end

return M
