local Util = require("ajans.util")

local M = {}

local have_proc = vim.uv.fs_stat("/proc/self") ~= nil
local have_ps, have_lsof = false, false
if vim.fn.has("win32") == 0 then
  have_ps = vim.fn.executable("ps") == 1
  have_lsof = vim.fn.executable("lsof") == 1
end

---@param pid number
function M.env(pid)
  local env = {} ---@type table<string, string>

  if have_proc then
    -- Linux: use /proc filesystem
    local e = io.open("/proc/" .. pid .. "/environ", "r")
    if e then
      local env_data = e:read("*all")
      e:close()
      local env_lines = vim.split(env_data, "\0")
      for _, env_line in ipairs(env_lines) do
        local k, v = env_line:match("^(.-)=(.*)$")
        if k and v then
          env[k] = v
        end
      end
    end
  end

  if have_ps then
    -- try ps as a fallback (macOS and others)
    local lines = Util.exec({ "ps", "eww", "-p", tostring(pid) })
    if lines and #lines > 0 then
      -- ps eww output is space-delimited, so values with spaces are best-effort.
      local line = lines[1]
      for k, v in line:gmatch("([%w_]+)=([^%s]+)") do
        env[k] = v
      end
    end
  end

  return next(env) and env or nil
end

---@param pid number
---@return integer?
function M.parent(pid)
  local ret = vim.api.nvim_get_proc(pid)
  return ret and ret.ppid or nil
end

---@param pid number
---@return integer[]
function M.children(pid)
  return vim.api.nvim_get_proc_children(pid) or {}
end

--- Get all descendant pids of the given pid, including itself
---@param pid number
function M.pids(pid)
  local ret = {} ---@type integer[]
  local todo = { pid }
  while #todo > 0 do
    local current = table.remove(todo, 1)
    ret[#ret + 1] = current
    vim.list_extend(todo, M.children(current))
  end
  return ret
end

---@param pid number
function M.cwd(pid)
  if have_proc then
    -- Linux: use /proc filesystem
    local ret = vim.uv.fs_readlink("/proc/" .. pid .. "/cwd")
    return ret and vim.fs.normalize(ret) or nil
  end

  if not have_lsof then
    return
  end

  -- try lsof as a fallback (macOS and others)
  local lines = Util.exec({ "lsof", "-a", "-d", "cwd", "-p", tostring(pid), "-Fn" })
  for _, line in ipairs(lines or {}) do
    -- lsof -Fn output format: n/path/to/cwd
    local path = line:match("^n(.+)$")
    if path then
      return vim.fs.normalize(path)
    end
  end
end

local proc_fields = { env = M.env, cwd = M.cwd }

---@param value string
---@return integer?, integer?
function M.parse_proc_stat(value)
  local pid, ppid = value:match("^(%d+) %(.+%) %S (%d+)")
  return tonumber(pid), tonumber(ppid)
end

---@param path string
---@return string?
local function read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return
  end
  local value = file:read("*all")
  file:close()
  return value
end

---@class ajans.cli.Proc
---@field pid number
---@field ppid number
---@field cmd string
---@field env? table<string, string>
---@field cwd? string

---@class ajans.cli.Procs
---@field _procs table<number,ajans.cli.Proc>
---@field _children table<number, number[]>
---@field _complete boolean
local P = {}
P.__index = P

---@param self ajans.cli.Procs
---@param pid integer
---@param ppid integer
---@param args string
local function add_proc(self, pid, ppid, args)
  self._procs[pid] = setmetatable({ pid = pid, ppid = ppid, cmd = args }, {
    __index = function(t, key)
      local field = proc_fields[key]
      if field then
        local value = field(t.pid) or false
        rawset(t, key, value)
        return value
      end
    end,
  })
  self._children[ppid] = self._children[ppid] or {}
  table.insert(self._children[ppid], pid)
end

---@param self ajans.cli.Procs
---@return boolean
local function update_from_proc(self)
  local ok, entries = pcall(vim.fs.dir, "/proc")
  if not ok or not entries then
    return false
  end
  local found = false
  local complete = true
  for name, kind in entries do
    if kind == "directory" and name:match("^%d+$") then
      local stat = read_file("/proc/" .. name .. "/stat")
      local pid, ppid
      if stat then
        pid, ppid = M.parse_proc_stat(stat)
      end
      if pid and ppid then
        local args = (read_file("/proc/" .. name .. "/cmdline") or ""):gsub("%z", " "):gsub("%s+$", "")
        if args == "" then
          args = (read_file("/proc/" .. name .. "/comm") or ""):gsub("%s+$", "")
        end
        if args == "" then
          complete = false
        else
          add_proc(self, pid, ppid, args)
          found = true
        end
      else
        complete = false
      end
    end
  end
  return found and complete
end

---@param opts? { force_proc?:boolean }
function P.new(opts)
  local self = setmetatable({}, P)
  self._procs = {}
  self._children = {}
  self:update(opts)
  return self
end

---@param opts? { force_proc?:boolean }
function P:update(opts)
  self._procs = {}
  self._children = {}
  self._complete = false
  if have_ps and not (opts and opts.force_proc) then
    local cmd = { "ps" }
    if (vim.env.USER or "") ~= "" then
      vim.list_extend(cmd, { "-u", vim.env.USER or "" })
    end
    vim.list_extend(cmd, { "-ww", "-o", "pid,ppid,args" })
    local lines = Util.exec(cmd)
    if lines then
      local complete = true
      for _, line in ipairs(vim.list_slice(lines, 2)) do -- skip header
        local pid, ppid, args = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
        if pid and ppid and args then
          add_proc(self, assert(tonumber(pid)), assert(tonumber(ppid)), args)
        elseif line ~= "" then
          complete = false
        end
      end
      if complete or not have_proc then
        self._complete = complete
        return
      end
      self._procs = {}
      self._children = {}
    end
  end
  if have_proc then
    self._complete = update_from_proc(self)
  end
end

---@return boolean
function P:is_complete()
  return self._complete
end

---@param pid number
---@return ajans.cli.Proc?
function P:get(pid)
  return self._procs[pid]
end

---@param pid number
function P:parent(pid)
  local proc = self:get(pid)
  return proc and self:get(proc.ppid) or nil
end

function P:list()
  return vim.tbl_values(self._procs)
end

---@param pid number
function P:children(pid)
  local children = self._children[pid] or {}
  local ret = {} ---@type ajans.cli.Proc[]
  for _, cpid in ipairs(children) do
    local proc = self:get(cpid)
    if proc then
      ret[#ret + 1] = proc
    end
  end
  return ret
end

---@param pid number
---@param cb? fun(proc: ajans.cli.Proc):(true|nil)
function P:walk(pid, cb)
  local todo = { pid }
  local ret = {} ---@type ajans.cli.Proc[]
  while #todo > 0 do
    local current = table.remove(todo, 1)
    local proc = self:get(current)
    if proc then
      if cb and cb(proc) then
        break
      end
      ret[#ret + 1] = proc
    end
    vim.list_extend(todo, self._children[current] or {})
  end
  return ret
end

---@param filter string|fun(proc: ajans.cli.Proc):boolean
function P:find(filter)
  if type(filter) == "string" then
    local pattern = filter --[[@as string]]
    ---@param proc ajans.cli.Proc
    filter = function(proc)
      return proc.cmd:find(pattern) ~= nil
    end
  end
  return vim.tbl_filter(filter, self._procs)
end

M.new = P.new

return M
