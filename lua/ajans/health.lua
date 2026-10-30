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

  local backend = require("ajans.cli.session").selected_backend()
  if backend == "herdr" then
    local Herdr = require("ajans.cli.session.herdr")
    local valid, message, version = Herdr.validate()
    if valid then
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
        if status.restart_needed == true then
          warn(
            "The running Herdr server uses a different compatible version; restart when convenient. "
              .. Herdr.RESTART_WARNING
          )
        end
        local socket, socket_err = Client.trusted_socket(status)
        if socket then
          ok("The selected Herdr server is running with a trusted local API socket")
        else
          error("The selected Herdr server API socket is unusable: " .. (socket_err or "unknown error"))
        end
        local Integrations = require("ajans.cli.session.herdr.integrations")
        local tools = require("ajans.config").tools()
        local tool_names = vim.tbl_keys(tools) ---@type string[]
        table.sort(tool_names)
        -- Report only tools that are configured, Herdr-registered, and actually
        -- installed; missing binaries have their own report further below.
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
      else
        ok("The selected Herdr server is stopped and will start when Ajans creates a session")
      end
    else
      error(message or "Selected terminal multiplexer `herdr` is unavailable")
    end
  elseif backend == "rex" then
    local Rex = require("ajans.cli.session.rex")
    local valid, message, version = Rex.validate()
    if valid then
      ok(("Selected terminal multiplexer `rex` %s is available"):format(version or "unknown"))
      local status, status_err = Rex.server_status()
      if not status then
        error("Unable to query the selected Rex server: " .. (status_err or "unknown error"))
      elseif status.running and not status.local_server then
        error(
          "The selected Rex server is remote; Ajans can only drive a local Rex server: " .. tostring(status.endpoint)
        )
      elseif status.running and (status.api_revision == nil or status.api_revision < Rex.MIN_API_REVISION) then
        error(
          ("The running Rex server reports API revision %s; Ajans requires >= %d; update Rex"):format(
            tostring(status.api_revision),
            Rex.MIN_API_REVISION
          )
        )
      elseif status.running then
        ok("The selected local Rex server is running")
      else
        ok("The selected Rex server is stopped and will start when Ajans creates a session")
      end
    else
      error(message or "Selected terminal multiplexer `rex` is unavailable")
    end
  elseif vim.fn.executable("tmux") == 1 then
    ok("Selected terminal multiplexer `tmux` is installed")
  else
    error("Selected terminal multiplexer `tmux` is not installed")
  end

  if backend == "tmux" and vim.fn.has("win32") == 0 then
    check_process_tools("tmux")
  elseif backend == "rex" and vim.fn.has("win32") == 0 then
    check_process_tools("Rex")
  end

  start("Ajans AI CLI Tools")
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

return M
