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
---@return integer?, integer?, integer?, integer?, string?
function M.parse_proc_stat(value)
  local pid, fields = value:match("^(%d+) %(.+%) (.+)$")
  if not pid or not fields then
    return
  end
  local values = vim.split(fields, "%s+", { trimempty = true })
  return tonumber(pid), tonumber(values[2]), tonumber(values[3]), tonumber(values[6]), values[20]
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

M._fs_dir = vim.fs.dir
M._read_file = read_file
M._fs_readlink = vim.uv.fs_readlink

---@class ajans.cli.Proc
---@field pid number
---@field ppid number
---@field cmd string
---@field argv? string[]
---@field executable? string
---@field runtime_executable? string
---@field start_time? string
---@field pgid? number
---@field tpgid? number
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
---@param metadata? {pgid?:number,tpgid?:number,start_time?:string,runtime_executable?:string}
local function add_proc(self, pid, ppid, args, metadata)
  metadata = metadata or {}
  local executable = args:match('^%s*"([^"]+)"') or args:match("^%s*'([^']+)'") or args:match("^%s*(%S+)")
  self._procs[pid] = setmetatable({
    pid = pid,
    ppid = ppid,
    cmd = args,
    executable = executable,
    runtime_executable = metadata.runtime_executable,
    start_time = metadata.start_time,
    pgid = metadata.pgid,
    tpgid = metadata.tpgid,
  }, {
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
---@param opts? {proc_root?:string}
---@return boolean
local function update_from_proc(self, opts)
  local root = opts and opts.proc_root or "/proc"
  local ok, entries = pcall(M._fs_dir, root)
  if not ok or not entries then
    return false
  end
  local found = false
  local complete = true
  for name, kind in entries do
    if kind == "directory" and name:match("^%d+$") then
      local stat = M._read_file(root .. "/" .. name .. "/stat")
      local pid, ppid, pgid, tpgid, start_time
      if stat then
        pid, ppid, pgid, tpgid, start_time = M.parse_proc_stat(stat)
      end
      if pid and ppid then
        local args = (M._read_file(root .. "/" .. name .. "/cmdline") or ""):gsub("%z", " "):gsub("%s+$", "")
        if args == "" then
          args = (M._read_file(root .. "/" .. name .. "/comm") or ""):gsub("%s+$", "")
        end
        if args == "" then
          complete = false
        else
          add_proc(self, pid, ppid, args, {
            pgid = pgid,
            tpgid = tpgid,
            start_time = start_time,
            runtime_executable = M._fs_readlink(root .. "/" .. name .. "/exe"),
          })
          found = true
        end
      else
        complete = false
      end
    end
  end
  return found and complete
end

---@param self ajans.cli.Procs
---@param lines string[]
local function update_from_ps(self, lines)
  local complete = true
  for _, line in ipairs(vim.list_slice(lines, 2)) do -- skip header
    local pid, ppid, pgid, tpgid, start_time, runtime_executable, args =
      line:match("^%s*(%d+)%s+(%d+)%s+([%-]?%d+)%s+([%-]?%d+)%s+(%S+%s+%S+%s+%S+%s+%S+%s+%S+)%s+(%S+)%s+(.*)$")
    if pid and ppid and args then
      add_proc(self, assert(tonumber(pid)), assert(tonumber(ppid)), args, {
        pgid = tonumber(pgid),
        tpgid = tonumber(tpgid),
        start_time = start_time,
        runtime_executable = runtime_executable,
      })
    else
      pid, ppid, args = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
      if pid and ppid and args then
        add_proc(self, assert(tonumber(pid)), assert(tonumber(ppid)), args)
      elseif line ~= "" then
        complete = false
      end
    end
  end
  self._complete = complete
end

---@return string[]?
function M.ps_command()
  if not have_ps then
    return
  end
  local cmd = { "ps" }
  if (vim.env.USER or "") ~= "" then
    vim.list_extend(cmd, { "-u", vim.env.USER or "" })
  end
  vim.list_extend(cmd, { "-ww", "-o", "pid,ppid,pgid,tpgid,lstart,comm,args" })
  return cmd
end

---@param stdout string
---@return ajans.cli.Procs
function M.from_ps_output(stdout)
  local self = setmetatable({ _procs = {}, _children = {}, _complete = false }, P)
  update_from_ps(self, vim.split(stdout, "\n", { plain = true, trimempty = true }))
  return self
end

---@param opts? { force_proc?:boolean, timeout?:integer, proc_root?:string }
function P.new(opts)
  local self = setmetatable({}, P)
  self._procs = {}
  self._children = {}
  self:update(opts)
  return self
end

---@param opts? { force_proc?:boolean, timeout?:integer, proc_root?:string }
function P:update(opts)
  self._procs = {}
  self._children = {}
  self._complete = false
  if have_ps and not (opts and opts.force_proc) then
    local lines = Util.exec(M.ps_command(), { timeout = opts and opts.timeout, notify = false })
    if lines then
      update_from_ps(self, lines)
      if self._complete or not have_proc then
        return
      end
      self._procs = {}
      self._children = {}
    end
  end
  if have_proc or (opts and opts.proc_root) then
    self._complete = update_from_proc(self, opts)
  end
end

---@return boolean
function P:is_complete()
  return self._complete
end

---@param proc ajans.cli.Proc
---@return table
function M.identity(proc)
  return {
    pid = proc.pid,
    start_time = proc.start_time,
    runtime_executable = proc.runtime_executable,
  }
end

---@param expected table?
---@param actual table?
---@return boolean
function M.same_identity(expected, actual)
  if not expected or not actual or expected.pid ~= actual.pid then
    return false
  end
  if expected.start_time and actual.start_time and expected.start_time ~= actual.start_time then
    return false
  end
  if
    expected.runtime_executable
    and actual.runtime_executable
    and vim.fs.normalize(expected.runtime_executable) ~= vim.fs.normalize(actual.runtime_executable)
  then
    return false
  end
  return true
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
