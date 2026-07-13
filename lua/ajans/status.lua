local M = {}

---@class ajans.cli.Status
---@field id string
---@field tool string
---@field cwd string
---@field backend string
---@field external boolean
---@field terminal boolean
---@field identity? string

local cli_sessions = {} ---@type table<string, ajans.cli.Status>
local cli_last_update = 0

local function normalize_cli_session(id, session)
  local tool = session.tool
  local ret = {
    id = session.id or id,
    tool = type(tool) == "table" and tool.name or tool,
    cwd = session.cwd,
  }
  local backend = session.mux_backend or session.backend
  if backend then
    ret.backend = backend
    ret.external = session.external == true
    ret.terminal = session.backend == "terminal"
  end
  ret.identity = session.mux_identity or session.identity
  return ret
end

local function update_cli_status()
  local Session = require("ajans.cli.session")
  cli_sessions = {}
  for id, session in pairs(Session.attached()) do
    cli_sessions[id] = normalize_cli_session(id, session)
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = require("ajans.config").augroup,
    pattern = { "AjansCliAttach", "AjansCliDetach" },
    callback = update_cli_status,
  })

  update_cli_status()
end

--- Get CLI session status
---@return ajans.cli.Status[]
function M.cli()
  local now = vim.uv.now()
  if now - cli_last_update > 5000 then
    cli_last_update = now
    -- update periodically to detect sessions where `is_running()` returns false
    -- can happen when an external process stopped
    update_cli_status()
  end
  return vim.tbl_values(cli_sessions)
end

return M
