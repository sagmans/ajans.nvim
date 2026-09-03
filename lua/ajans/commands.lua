local Util = require("ajans.util")

local M = {}

---@alias ajans.command.Args table<string, any>
---@alias ajans.command.Fn fun(args: ajans.command.Args)
---@alias ajans.command.Cmd ajans.command.Fn | table<string, ajans.command.Cmd>

---@type ajans.command.Cmd
M.commands = {
  cli = {
    show = function(opts)
      require("ajans.cli").show(opts)
    end,
    toggle = function(opts)
      require("ajans.cli").toggle(opts)
    end,
    hide = function(opts)
      require("ajans.cli").hide(opts)
    end,
    close = function(opts)
      require("ajans.cli").close(opts)
    end,
    focus = function(opts)
      require("ajans.cli").focus(opts)
    end,
    select = function(opts)
      require("ajans.cli").select(opts)
    end,
    send = function(opts)
      require("ajans.cli").send(opts)
    end,
    prompt = function()
      require("ajans.cli").prompt()
    end,
    retry = function(opts)
      require("ajans.cli").retry(opts)
    end,
  },
}

---@param str string
---@return string
local function strip_strings(str)
  local ret = {} ---@type string[]
  local i = 1
  while i <= #str do
    local char = str:sub(i, i)
    if char == '"' or char == "'" then
      ret[#ret + 1] = char
      i = i + 1
      while i <= #str do
        local inner = str:sub(i, i)
        if inner == "\\" then
          i = i + 2
        elseif inner == char then
          ret[#ret + 1] = char
          i = i + 1
          break
        else
          i = i + 1
        end
      end
    else
      ret[#ret + 1] = char
      i = i + 1
    end
  end
  return table.concat(ret)
end

---@param str string
---@param opts? {error?: boolean}
function M.argparse(str, opts)
  ---@type ajans.command.Args
  local ret, ok = {}, true
  local env = setmetatable({}, {
    __newindex = function(_, k, v)
      ret[k] = v
    end,
    __index = function(_, k)
      return k
    end,
  })
  local function on_error(err)
    ok = false
    return (opts or {}).error ~= false and Util.error(("Invalid args: `%s`\nError: %s"):format(str, err))
  end
  xpcall(function()
    local code = strip_strings(str)
    if
      code:find("[%a_][%w_]*%s*[%.:]%s*[%a_][%w_]*")
      or code:find("[%)%}%]]%s*[%.:]%s*[%a_]")
      or code:find("[\"']%s*[%.:]%s*[%a_]")
    then
      return on_error("field access is not allowed")
    end
    local chunk, err = load(str, "ajans", "t", env)
    return chunk and (chunk() or true) or on_error(err)
  end, on_error)
  return ok and ret or nil
end

---@param str string
---@param opts? {error?: boolean}
---@overload fun(str: string): ajans.command.Fn, ajans.command.Args?
---@overload fun(str: string): string[]
function M.parse(str, opts)
  local parts = vim.split(str, "%s+")
  local cmd = M.commands
  while #parts > 0 and type(cmd) == "table" do
    if cmd[parts[1]] then
      cmd = cmd[table.remove(parts, 1)]
    else
      break
    end
  end
  if type(cmd) == "function" then
    return cmd, M.argparse(table.concat(parts, " "), opts)
  end
  local prefix = #parts > 0 and parts[1] or ""
  ---@param key string
  return vim.tbl_filter(function(key)
    return key:find(prefix) == 1 and key ~= "debug"
  end, vim.tbl_keys(cmd))
end

---@param line string
function M.complete(line)
  line = line:gsub("^%s*Ajans%s+", "")
  local cmd = M.parse(line, { error = false })
  return type(cmd) == "table" and cmd or {}
end

---@param line vim.api.keyset.create_user_command.command_args
function M.cmd(line)
  local cmd, args = M.parse(line.args or "")
  if type(cmd) == "function" and args then
    if line.range and line.range > 0 then
      vim.fn.feedkeys("gv", "nx") -- restore visual selection
    end
    cmd(args)
  elseif type(cmd) == "table" and #cmd > 0 then
    Util.error(("Incomplete command: `%s`\nExpecting: `[%s]`"):format(line.args or "", table.concat(cmd, "|")))
  elseif type(cmd) ~= "function" then
    Util.error(("Invalid command: `%s`"):format(line.args or ""))
  end
end

return M
