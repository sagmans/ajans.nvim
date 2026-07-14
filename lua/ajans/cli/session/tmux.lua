local Config = require("ajans.config")
local Procs = require("ajans.cli.procs")
local Util = require("ajans.util")

---@class ajans.cli.muxer.Tmux: ajans.cli.Session
---@field tmux_pane_id string
---@field tmux_pid number
local M = {}
M.__index = M

local PANE_FORMAT =
  "#{session_id}:#{pane_id}:#{pane_pid}:#{session_name}:#{?pane_current_path,#{pane_current_path},#{pane_start_path}}"

---@return ajans.cli.terminal.Cmd?
function M:attach()
  if self.sid == self.mux_session then
    return { cmd = { "tmux", "attach-session", "-t", self.sid } }
  end
end

function M:init()
  if self.started then
    self.external = self.sid ~= self.mux_session
  else
    self.external = vim.env.TMUX and Config.cli.mux.create ~= "terminal"
    self.mux_session = self.sid
  end
  self.priority = self.external and 10 or 50
end

---@return ajans.cli.terminal.Cmd? cmd
---@return boolean started
function M:start()
  if not self.external then
    local cmd = { "tmux", "new", "-A", "-s", self.id }
    vim.list_extend(cmd, { "-c", self.cwd })
    self:add_cmd(cmd)
    vim.list_extend(cmd, { ";", "set-option", "status", "off" })
    vim.list_extend(cmd, { ";", "set-option", "detach-on-destroy", "on" })
    return { cmd = cmd }, true
  elseif Config.cli.mux.create == "window" then
    local cmd = { "tmux", "new-window", "-dP", "-c", self.cwd, "-F", PANE_FORMAT }
    self:add_cmd(cmd)
    self:spawn(cmd)
    Util.info(("Started **%s** in a new tmux window"):format(self.tool.name))
  elseif Config.cli.mux.create == "split" then
    local cmd = { "tmux", "split-window", "-dP", "-c", self.cwd, "-F", PANE_FORMAT }
    cmd[#cmd + 1] = Config.cli.mux.split.vertical and "-h" or "-v"
    local size = Config.cli.mux.split.size
    vim.list_extend(cmd, { "-l", tostring(size <= 1 and ((size * 100) .. "%") or size) })
    self:add_cmd(cmd)
    self:spawn(cmd)
    Util.info(("Started **%s** in a new tmux split"):format(self.tool.name))
  end
  return nil, self.started == true
end

--- Execute the given tmux command and update the session info,
--- based on the first pane returned.
---@param cmd string[]
function M:spawn(cmd)
  local pane = M.panes({ cmd = cmd, notify = true })[1]
  if pane then
    self.id = pane.state_id
    self.tmux_pane_id = pane.id
    self.mux_session = pane.session_name
    self.tmux_pid = pane.pid
    self.started = true
  end
end

function M:detach() end

function M:is_running()
  return self.tmux_pid and vim.api.nvim_get_proc(self.tmux_pid) ~= nil
end

function M:accepts_automated_input()
  if not self.tmux_pid or type(self.tool.is_proc) ~= "function" then
    return false
  end
  local pane_id = self:pane_id()
  local lines = pane_id
    and Util.exec({
      "tmux",
      "display-message",
      "-p",
      "-t",
      pane_id,
      "#{pane_pid}:#{pane_current_command}",
    }, { notify = false })
  local pane_pid, current
  if lines and lines[1] then
    pane_pid, current = lines[1]:match("^(%d+):(.*)$")
  end
  if tonumber(pane_pid) ~= self.tmux_pid or not current or current == "" then
    return false
  end
  local matched_pid
  Procs.new():walk(self.tmux_pid, function(proc)
    if self.tool:is_proc(proc) and proc.cmd:find(current, 1, true) then
      if self._authorized_pid == proc.pid then
        matched_pid = proc.pid
        return true
      end
      matched_pid = matched_pid or proc.pid
    end
  end)
  if self._authorized_pid then
    return matched_pid == self._authorized_pid
  end
  self._authorized_pid = matched_pid
  return matched_pid ~= nil
end

---@param ret string[]
function M:add_cmd(ret)
  for key, value in pairs(self.tool.env or {}) do
    if value == false then
      vim.list_extend(ret, { "-u", key }) -- unset
    else
      vim.list_extend(ret, { "-e", ("%s=%s"):format(key, tostring(value)) })
    end
  end
  vim.list_extend(ret, self.tool.cmd)
end

---@param opts? { cmd?:string[], notify?:boolean }
---@return ajans.tmux.Pane[], boolean
function M.panes(opts)
  opts = opts or {}
  -- List all panes in current session with their command and cwd
  local cmd = opts.cmd or { "tmux", "list-panes", "-a", "-F", PANE_FORMAT }
  local lines = Util.exec(cmd, { notify = opts.notify == true })
  local panes = {} ---@type ajans.tmux.Pane[]
  local complete = lines ~= nil
  for _, line in ipairs(lines or {}) do
    local session_id, id, pid, session_name, cwd = line:match("^(%$%d+):(%%%d+):(%d+):(.-):(.*)$")
    if id and pid and session_name and cwd then
      pid = assert(tonumber(pid), "invalid tmux pane_pid: " .. pid) --[[@as number]]
      ---@class ajans.tmux.Pane
      panes[#panes + 1] = {
        state_id = ("tmux %s"):format(pid), -- unique id for the pane state
        pid = pid, -- process id of the pane
        id = id, -- tmux pane id
        session_name = session_name,
        session_id = session_id,
        cwd = cwd,
      }
    else
      complete = false
    end
  end
  return panes, complete
end

---@return table<string,integer[]>, boolean
function M.clients()
  local lines = Util.exec({ "tmux", "list-clients", "-F", "#{session_id}:#{client_pid}" }, { notify = false })
  local ret = {} ---@type table<string,integer[]>
  local complete = lines ~= nil
  for _, line in ipairs(lines or {}) do
    local session_id, pid = line:match("^(%$%d+):(%d+)$")
    if session_id and pid then
      pid = assert(tonumber(pid), "invalid tmux client_pid: " .. pid) --[[@as number]]
      ret[session_id] = ret[session_id] or {}
      table.insert(ret[session_id], pid)
    else
      complete = false
    end
  end
  return ret, complete
end

function M.sessions()
  local panes, panes_complete = M.panes()
  local ret = {} ---@type ajans.cli.session.State[]
  local tools = Config.tools()

  local clients, clients_complete = M.clients()

  local procs = Procs.new()
  for _, pane in ipairs(panes) do
    procs:walk(pane.pid, function(proc)
      for _, tool in pairs(tools) do
        if tool:is_proc(proc) then
          local pids = Procs.pids(pane.pid)
          vim.list_extend(pids, clients[pane.session_id] or {})
          ret[#ret + 1] = {
            id = pane.state_id,
            cwd = proc.cwd or pane.cwd,
            tool = tool,
            tmux_pane_id = pane.id,
            tmux_pid = pane.pid,
            mux_session = pane.session_name,
            pids = pids,
          }
          return true
        end
      end
    end)
  end

  local procs_complete = not procs.is_complete or procs:is_complete()
  return ret, panes_complete ~= false and clients_complete ~= false and procs_complete
end

function M:pane_id()
  if self.tmux_pane_id then
    return self.tmux_pane_id
  end
  if not self.external then
    self:spawn({ "tmux", "list-panes", "-s", "-F", PANE_FORMAT, "-t", self.mux_session })
  end
  return self.tmux_pane_id
end

function M:_drain_input()
  if self._sending then
    return
  end
  self._input_queue = self._input_queue or {}
  local item = table.remove(self._input_queue, 1)
  if not item then
    return
  end
  local pane_id = self:pane_id()
  if not pane_id or (self._authorized_pid and not self:accepts_automated_input()) then
    self._last_send_ok = false
    self._input_queue = {}
    return
  end
  self._sending = true

  local function complete(ok)
    if ok and item.kind == "text" then
      self._last_send_ok = true
    elseif not ok then
      self._last_send_ok = false
      self._input_queue = {}
    end
    self._sending = false
    self:_drain_input()
  end
  if item.kind == "submit" then
    if self._last_send_ok == false then
      self._last_send_ok = nil
      complete(false)
      return
    end
    self._last_send_ok = nil
    complete(Util.exec({ "tmux", "send-keys", "-t", pane_id, "Enter" }) ~= nil)
    return
  end

  local function send_text()
    if self._authorized_pid and not self:accepts_automated_input() then
      complete(false)
      return
    end
    local buffer = "ajans-" .. pane_id
    if Util.exec({ "tmux", "load-buffer", "-b", buffer, "-" }, { stdin = item.text }) == nil then
      complete(false)
      return
    end
    complete(Util.exec({ "tmux", "paste-buffer", "-b", buffer, "-d", "-r", "-t", pane_id }) ~= nil)
  end
  if self.tool.mux_focus then
    if Util.exec({ "tmux", "send-keys", "-t", pane_id, "Escape", "[", "I" }) == nil then
      complete(false)
      return
    end
    vim.defer_fn(send_text, 50)
  else
    send_text()
  end
end

---Send text to a tmux pane
function M:send(text)
  self._input_queue = self._input_queue or {}
  self._input_queue[#self._input_queue + 1] = { kind = "text", text = text }
  self:_drain_input()
end

---Submit after all queued text reaches the tmux pane.
function M:submit()
  self._input_queue = self._input_queue or {}
  self._input_queue[#self._input_queue + 1] = { kind = "submit" }
  self:_drain_input()
end

function M:dump()
  local pane_id = self:pane_id()
  if not pane_id then
    return
  end
  local _, ret =
    Util.exec({ "tmux", "capture-pane", "-p", "-t", pane_id, "-S", "-" .. Config.cli.mux.dump, "-E", "-", "-e" })
  return ret
end

return M
