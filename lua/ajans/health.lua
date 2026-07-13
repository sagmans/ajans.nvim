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
      local status = Herdr.server_status()
      if status and status.running and status.compatible == false then
        error("The running Herdr server is incompatible with the installed client; restart the Herdr server")
      elseif status and status.running and status.restart_needed == true then
        error("The running Herdr server uses a different version; restart the Herdr server")
      elseif status and status.running then
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
    for _, command in ipairs({ "ps", "lsof" }) do
      if vim.fn.executable(command) == 1 then
        ok("`" .. command .. "` is installed")
      else
        warn("`" .. command .. "` is not installed, running processes and ports will not be detected")
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
