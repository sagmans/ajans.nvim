local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

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
      elseif status.running and status.restart_needed == true then
        error("The running Herdr server uses a different version; restart the Herdr server. " .. Herdr.RESTART_WARNING)
      elseif status.running then
        ok("The selected Herdr server is running")
      else
        ok("The selected Herdr server is stopped and will start when Ajans creates a session")
      end
    else
      error(message or "Selected terminal multiplexer `herdr` is unavailable")
    end
  elseif vim.fn.executable("tmux") == 1 then
    ok("Selected terminal multiplexer `tmux` is installed")
  else
    error("Selected terminal multiplexer `tmux` is not installed")
  end

  if backend == "tmux" and vim.fn.has("win32") == 0 then
    local linux = vim.fn.has("linux") == 1
    if vim.fn.executable("ps") == 1 then
      ok("`ps` is installed")
    elseif linux then
      ok("`ps` is not installed; using `/proc` for process discovery")
    else
      warn("`ps` is not installed; tmux process discovery is unavailable")
    end
    if not linux then
      if vim.fn.executable("lsof") == 1 then
        ok("`lsof` is installed")
      else
        warn("`lsof` is not installed; tmux working-directory detection is unavailable")
      end
    end
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
