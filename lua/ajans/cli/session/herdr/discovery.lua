local Config = require("ajans.config")
local Util = require("ajans.util")

local M = {}

---@class ajans.herdr.DiscoveryBackend
---@field request fun(args:string[], opts?:table):table?, string?
---@field supports_snapshot fun():boolean
---@field _run_many fun(commands:string[][]):vim.SystemCompleted[]

local AGENT_PREFIX = "ajans:"
local LABEL_ALIASES = {
  ["github-copilot"] = "copilot",
  ["github copilot"] = "copilot",
}

---@param label string?
---@return string?
function M.tool_name_for_label(label)
  if type(label) ~= "string" then
    return
  end
  local normalized = label:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local name = LABEL_ALIASES[normalized] or normalized:gsub("[%s%-]+", "_")
  return Config.cli.tools[name] ~= nil and name or nil
end

---@param name string?
---@return string?
local function tool_name_for_owned_agent(name)
  if type(name) ~= "string" then
    return
  end
  local tool = name:match("^" .. AGENT_PREFIX .. "([^%s]+)")
  return tool and Config.cli.tools[tool] ~= nil and tool or nil
end

---@param values integer[]
---@param value any
local function add_pid(values, value)
  value = tonumber(value)
  if value and not vim.tbl_contains(values, value) then
    values[#values + 1] = value
  end
end

---@param process_info table?
---@return integer[]
function M.process_pids(process_info)
  local pids = {}
  if type(process_info) ~= "table" then
    return pids
  end
  add_pid(pids, process_info.shell_pid)
  add_pid(pids, process_info.foreground_process_group_id)
  for _, process in ipairs(process_info.foreground_processes or {}) do
    add_pid(pids, process.pid)
  end
  return pids
end

---@param process table
---@return ajans.cli.Proc
function M.to_proc(process)
  local cmd = process.cmdline
  if type(cmd) ~= "string" or cmd == "" then
    cmd = type(process.argv) == "table" and #process.argv > 0 and table.concat(process.argv, " ")
      or process.argv0
      or process.name
      or ""
  end
  return {
    pid = tonumber(process.pid) or 0,
    ppid = 0,
    cmd = cmd,
    cwd = process.cwd,
  }
end

---@param backend ajans.herdr.DiscoveryBackend
---@param pane table
---@param opts? table
---@return table?
function M.pane_process_info(backend, pane, opts)
  opts = vim.tbl_extend("force", { notify = false }, opts or {})
  local result, err = backend.request({ "pane", "process-info", "--pane", pane.pane_id }, opts)
  if type(result) ~= "table" then
    if err and not err:find("pane_not_found", 1, true) and not err:find("not found", 1, true) then
      Util.error(("Failed to inspect Herdr pane `%s`: %s"):format(pane.pane_id, err))
    end
    return
  end
  if type(result.process_info) ~= "table" then
    Util.error(("Herdr process-info response for pane `%s` is missing `process_info`"):format(pane.pane_id))
    return
  end
  return result.process_info
end

---@param result vim.SystemCompleted
---@return string
local function result_error(result)
  local output = result.stderr ~= "" and result.stderr or result.stdout
  return tostring(output or "unknown error"):gsub("%s+$", "")
end

---@param backend ajans.herdr.DiscoveryBackend
---@param panes table[]
---@return table<string,table>, boolean
local function pane_process_infos(backend, panes)
  local commands = {}
  for _, pane in ipairs(panes) do
    commands[#commands + 1] = { "herdr", "pane", "process-info", "--pane", pane.pane_id }
  end
  local ok, results = pcall(backend._run_many, commands)
  if not ok then
    Util.error("Failed to inspect Herdr panes: " .. tostring(results))
    return {}, false
  end
  local infos = {}
  local failures = 0
  local first_failure
  for index, pane in ipairs(panes) do
    local result = results[index]
    local decoded_ok, value = pcall(vim.json.decode, result and result.stdout or "")
    local info = decoded_ok and value and value.result and value.result.process_info
    if type(info) == "table" then
      infos[pane.pane_id] = info
    elseif result and result.code ~= 0 then
      local err = result_error(result)
      if not err:find("pane_not_found", 1, true) and not err:find("not found", 1, true) then
        failures = failures + 1
        first_failure = first_failure or ("pane `%s`: %s"):format(pane.pane_id, err)
      end
    else
      failures = failures + 1
      first_failure = first_failure or ("pane `%s`: malformed response"):format(pane.pane_id)
    end
  end
  if failures > 0 then
    Util.error(("Failed to inspect %d Herdr pane(s); first failure: %s"):format(failures, first_failure))
  end
  return infos, failures == 0
end

---@param pane table
---@param agent table?
---@param tools table<string,ajans.cli.Tool>
---@param tool_names string[]
---@param info table?
---@return ajans.cli.Tool?, ajans.cli.Proc?
local function match_pane(pane, agent, tools, tool_names, info)
  local name = tool_name_for_owned_agent(agent and agent.name)
  if name then
    return tools[name]
  end
  local labels = { agent and agent.agent, agent and agent.display_agent, pane.agent, pane.display_agent }
  for index = 1, 4 do
    name = M.tool_name_for_label(labels[index])
    if name then
      return tools[name]
    end
  end
  for _, process in ipairs((info and info.foreground_processes) or {}) do
    local proc = M.to_proc(process)
    for _, tool_name in ipairs(tool_names) do
      if tools[tool_name]:is_proc(proc) then
        return tools[tool_name], proc
      end
    end
  end
end

---@param backend ajans.herdr.DiscoveryBackend
---@param resource "workspace"|"tab"|"pane"|"agent"
---@param field "workspaces"|"tabs"|"panes"|"agents"
---@return table[]?, string?
local function legacy_list(backend, resource, field)
  local result, err = backend.request({ resource, "list" }, { stopped_ok = true })
  if not result then
    return nil, err
  end
  if type(result[field]) ~= "table" then
    Util.error(("Herdr %s list response is missing `%s`"):format(resource, field))
    return nil, "malformed legacy inventory"
  end
  return result[field]
end

---@param backend ajans.herdr.DiscoveryBackend
---@return table?, string?
function M.snapshot(backend)
  if backend.supports_snapshot() then
    local result, err = backend.request({ "api", "snapshot" }, { stopped_ok = true })
    if not result then
      return nil, err
    end
    if type(result.snapshot) ~= "table" then
      Util.error("Herdr snapshot response is missing `snapshot`")
      return nil, "malformed snapshot"
    end
    for _, field in ipairs({ "workspaces", "tabs", "panes", "agents" }) do
      if type(result.snapshot[field]) ~= "table" then
        Util.error(("Herdr snapshot response is missing `%s`"):format(field))
        return nil, "malformed snapshot"
      end
    end
    return result.snapshot
  end

  local snapshot = {}
  for _, item in ipairs({
    { resource = "workspace", field = "workspaces" },
    { resource = "tab", field = "tabs" },
    { resource = "pane", field = "panes" },
    { resource = "agent", field = "agents" },
  }) do
    local values, err = legacy_list(backend, item.resource, item.field)
    if not values then
      return nil, err
    end
    snapshot[item.field] = values
  end
  return snapshot
end

---@param backend ajans.herdr.DiscoveryBackend
---@return ajans.cli.session.State[], boolean
function M.sessions(backend)
  local snapshot, err = M.snapshot(backend)
  if not snapshot then
    return {}, err == "stopped"
  end

  local malformed_inventory = false
  local agents = {}
  for _, agent in ipairs(snapshot.agents) do
    if agent.pane_id then
      agents[agent.pane_id] = agent
    else
      malformed_inventory = true
    end
  end
  local workspaces = {}
  for _, workspace in ipairs(snapshot.workspaces) do
    if workspace.workspace_id then
      workspaces[workspace.workspace_id] = workspace
    else
      malformed_inventory = true
    end
  end
  local tabs = {}
  for _, tab in ipairs(snapshot.tabs) do
    if tab.tab_id then
      tabs[tab.tab_id] = tab
    else
      malformed_inventory = true
    end
  end

  local panes = {}
  local malformed_pane = false
  for _, pane in ipairs(snapshot.panes) do
    if pane.pane_id and pane.terminal_id and pane.workspace_id and pane.tab_id then
      panes[#panes + 1] = pane
    else
      malformed_pane = true
    end
  end

  local tools = Config.tools()
  local tool_names = vim.tbl_keys(tools)
  table.sort(tool_names)
  local classified = {}
  local unmatched = {}
  for _, pane in ipairs(panes) do
    local tool = match_pane(pane, agents[pane.pane_id], tools, tool_names)
    if tool then
      classified[pane.pane_id] = tool
    else
      unmatched[#unmatched + 1] = pane
    end
  end
  local process_infos, process_complete = pane_process_infos(backend, unmatched)
  local sessions = {}
  for _, pane in ipairs(panes) do
    local agent = agents[pane.pane_id]
    local process_info = process_infos[pane.pane_id] or pane.process_info or (agent and agent.process_info)
    local tool = classified[pane.pane_id]
    local proc
    if not tool then
      tool, proc = match_pane(pane, agent, tools, tool_names, process_info)
    end
    if tool then
      local cwd = proc and proc.cwd
        or agent and (agent.foreground_cwd or agent.cwd)
        or pane.foreground_cwd
        or pane.cwd
        or vim.uv.cwd()
      local name = agent and agent.name
      local placement
      if name and workspaces[pane.workspace_id] and workspaces[pane.workspace_id].label == name then
        placement = "workspace"
      elseif name and tabs[pane.tab_id] and tabs[pane.tab_id].label == name then
        placement = "tab"
      elseif name and name:find("^" .. AGENT_PREFIX) then
        placement = "split"
      end
      sessions[#sessions + 1] = {
        id = "herdr " .. pane.terminal_id,
        identity = "herdr:" .. pane.terminal_id,
        cwd = cwd,
        tool = tool,
        pids = M.process_pids(process_info),
        mux_session = pane.workspace_id,
        herdr_terminal_id = pane.terminal_id,
        herdr_pane_id = pane.pane_id,
        herdr_workspace_id = pane.workspace_id,
        herdr_tab_id = pane.tab_id,
        herdr_agent = agent ~= nil,
        herdr_name = name,
        herdr_label = agent and (agent.agent or agent.display_agent),
        herdr_agent_session = agent and agent.agent_session,
        herdr_placement = placement,
      }
    end
  end
  if malformed_pane then
    Util.error("Herdr snapshot contains a pane without stable terminal, pane, workspace, or tab IDs")
  end
  if malformed_inventory then
    Util.error("Herdr snapshot contains a workspace, tab, or agent without a stable ID")
  end
  return sessions, process_complete and not malformed_pane and not malformed_inventory
end

return M
