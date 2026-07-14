local Config = require("ajans.config")
local Text = require("ajans.text")

---@class ajans.cli.Tool: ajans.cli.Config
---@field config ajans.cli.Config
---@field name string
local M = {}
M.__index = M

---@type table<string,ajans.cli.Config>
local base = setmetatable({}, {
  __index = function(t, key)
    local f = vim.api.nvim_get_runtime_file("aj/cli/" .. key .. ".lua", false)[1]
    if f then
      local ok, ret = pcall(dofile, f)
      if ok and type(ret) == "table" then
        rawset(t, key, ret)
      end
    end
    return rawget(t, key)
  end,
})

---@param proc ajans.cli.Proc
---@return string
local function executable_name(proc)
  local executable = proc.executable
  if type(executable) ~= "string" or executable == "" then
    executable = proc.cmd:match('^%s*"([^"]+)"') or proc.cmd:match("^%s*'([^']+)'") or proc.cmd:match("^%s*(%S+)") or ""
  end
  return vim.fs.basename(executable)
end

---@param name string
function M.get(name)
  local config =
    vim.tbl_deep_extend("force", vim.deepcopy(base[name] or {}), vim.deepcopy(Config.cli.tools[name] or {}))
  local self = setmetatable(vim.deepcopy(config), M) --[[@as ajans.cli.Tool]]
  self.config = config
  self.is_proc = nil
  self.format = nil
  self.name = name
  return self
end

---@param proc ajans.cli.Proc
function M:is_proc(proc)
  local is_proc = self.config.is_proc
  if type(is_proc) == "string" then
    local ok, re = pcall(vim.regex, is_proc)
    if ok then
      is_proc = function(_, p)
        local executable = executable_name(p)
        local start, finish = re:match_str(executable)
        return start == 0 and finish == #executable
      end
    else
      is_proc = function()
        return false
      end
    end
    self.config.is_proc = is_proc
  end
  return type(is_proc) == "function" and is_proc(self, proc) or false
end

---@param opts? ajans.cli.Config
function M:clone(opts)
  local clone = vim.tbl_deep_extend("force", vim.deepcopy(self), opts or {})
  return setmetatable(clone, M) --[[@as ajans.cli.Tool]]
end

---@param text ajans.Text[]
function M:format(text)
  local ret = Text.to_string(text)
  if type(self.config.format) == "function" then
    local str = self.config.format(text, ret)
    ret = str or Text.to_string(text)
  end
  return ret
end

return M
