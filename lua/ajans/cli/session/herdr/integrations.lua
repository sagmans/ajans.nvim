local Util = require("ajans.util")

-- Herdr ships optional per-agent hooks ("integrations") that report agent
-- lifecycle and session identity. Ajans never installs or modifies them; it
-- only reads status output and advises the user when a tool it is about to
-- drive lacks a current integration.
local M = {}

local STATUS_COMMAND = { "herdr", "integration", "status" }

-- Only tools Ajans prioritizes and Herdr supports end-to-end get guidance;
-- kinds without an installer (cline, kimi, amp, maki, ...) stay unmapped so
-- Ajans can never suggest installing something Herdr does not provide.
local TOOL_INTEGRATIONS = {
  antigravity = "antigravity-cli",
  pi = "pi",
}

M.STATE_CURRENT = "current"
M.STATE_MISSING = "missing"
M.STATE_STALE = "stale"
M.STATE_UNKNOWN = "unknown"

-- Warnings deduplicate per tool+state so a persistent gap warns once; a
-- changed state must be able to warn again.
local last_advised = {}

---@param tool_name string
---@return string? target
function M.integration_for(tool_name)
  return TOOL_INTEGRATIONS[tool_name]
end

---Classify one `<target>: <detail>` status line.
---@param detail string
---@return string state
local function classify(detail)
  local normalized = detail:lower()
  if normalized:find("^current") then
    return M.STATE_CURRENT
  elseif normalized:find("^not installed") then
    return M.STATE_MISSING
  elseif normalized:find("^stale") or normalized:find("^outdated") then
    return M.STATE_STALE
  end
  return M.STATE_UNKNOWN
end

---Parse `herdr integration status` text into target -> { state, detail }.
---@param text string?
---@return table<string, table>
function M.parse(text)
  local statuses = {}
  if type(text) ~= "string" then
    return statuses
  end
  for line in text:gmatch("[^\r\n]+") do
    local target, detail = line:match("^(%S+):%s+(.+)$")
    if target and detail then
      statuses[target] = { state = classify(detail), detail = detail }
    end
  end
  return statuses
end

---@param run fun(cmd:string[]):{ code:integer, stdout:string, stderr:string }
---@return string? text
---@return string? error
function M.status_text(run)
  local ok, result = pcall(run, STATUS_COMMAND)
  if not ok then
    return nil, tostring(result)
  end
  if type(result) ~= "table" then
    return nil, "unexpected runner result"
  end
  if result.code ~= 0 then
    local output = result.stderr ~= "" and result.stderr or result.stdout
    local message = type(output) == "string" and vim.trim(output) or ""
    return nil, message ~= "" and message or "herdr integration status failed"
  end
  return result.stdout
end

---Assess the integration backing a configured Ajans tool.
---@param tool_name string
---@param run fun(cmd:string[]):{ code:integer, stdout:string, stderr:string }
---@return table? assessment # { state:string, target:string, detail?:string, query_error?:string }
function M.assess(tool_name, run)
  local target = M.integration_for(tool_name)
  if not target then
    return
  end
  local text, err = M.status_text(run)
  if not text then
    return { state = M.STATE_UNKNOWN, target = target, query_error = err }
  end
  local entry = M.parse(text)[target]
  if not entry then
    return { state = M.STATE_UNKNOWN, target = target, detail = "missing from status output" }
  end
  return { state = entry.state, target = target, detail = entry.detail }
end

---Build guidance for a non-current state. Install commands exist only for
--- states Herdr can act on; unknown states get the read-only status command.
---@param assessment table
---@return string
function M.message(assessment)
  if assessment.state == M.STATE_MISSING or assessment.state == M.STATE_STALE then
    local verb = assessment.state == M.STATE_MISSING and "is not installed" or "is outdated"
    return ("Herdr's `%s` integration %s; run `herdr integration install %s` to improve agent lifecycle reporting. Integrations never sign in, trust folders, or authorize terminal input."):format(
      assessment.target,
      verb,
      assessment.target
    )
  end
  return ("Unable to determine the state of Herdr's `%s` integration; run `herdr integration status`."):format(
    assessment.target
  )
end

---Advisory-only notice for tools Ajans is about to drive. Current integrations
---stay silent and query failures stay quiet (the health check reports those);
--- deduplicated so repeated starts do not nag.
---@param tool_name string
---@param run fun(cmd:string[]):{ code:integer, stdout:string, stderr:string }
---@return boolean warned
function M.advise(tool_name, run)
  local assessment = M.assess(tool_name, run)
  if not assessment or assessment.state == M.STATE_CURRENT or assessment.query_error then
    return false
  end
  local key = assessment.state .. ":" .. (assessment.detail or "")
  if last_advised[tool_name] == key then
    return false
  end
  last_advised[tool_name] = key
  Util.warn(M.message(assessment))
  return true
end

---Forget deduplicated warnings (used by tests and config reloads).
function M.reset()
  last_advised = {}
end

return M
