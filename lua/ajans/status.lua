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
local cli_update_pending = false

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

local function update_cli_status(sessions)
  cli_sessions = {}
  for id, session in pairs(sessions) do
    cli_sessions[id] = normalize_cli_session(id, session)
  end
  cli_last_update = vim.uv.now()
end

local function update_cli_snapshot()
  update_cli_status(require("ajans.cli.session").attached_snapshot())
end

local function schedule_cli_update()
  if cli_update_pending then
    return
  end
  cli_update_pending = true
  vim.schedule(function()
    require("ajans.cli.session").attached_async(function(sessions)
      cli_update_pending = false
      update_cli_status(sessions)
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd("User", {
    group = require("ajans.config").augroup,
    pattern = { "AjansCliAttach", "AjansCliDetach" },
    callback = update_cli_snapshot,
  })

  update_cli_snapshot()
end

--- Get CLI session status
---@return ajans.cli.Status[]
function M.cli()
  local now = vim.uv.now()
  if now - cli_last_update > 5000 then
    -- Statusline renders must stay non-blocking even when a mux server stalls.
    -- Refresh the cache after returning the current snapshot.
    cli_last_update = now
    schedule_cli_update()
  end
  return vim.tbl_values(cli_sessions)
end

return M
