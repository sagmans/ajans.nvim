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

local INTERPRETERS = {
  bash = true,
  fish = true,
  node = true,
  perl = true,
  python = true,
  python3 = true,
  ruby = true,
  sh = true,
  zsh = true,
}

---@param value string?
---@return string
local function basename(value)
  return type(value) == "string" and value ~= "" and vim.fs.basename(value) or ""
end

---@param proc ajans.cli.ProcessMatch
---@return string[], {start:integer,finish:integer}[]
local function command_tokens(proc)
  local command = proc.cmd or ""
  local argv = {}
  local spans = {}
  local index = 1
  while index <= #command do
    while index <= #command and command:sub(index, index):match("%s") do
      index = index + 1
    end
    if index > #command then
      break
    end
    local start = index
    local quote
    local token = {}
    while index <= #command do
      local char = command:sub(index, index)
      if quote then
        if char == quote then
          quote = nil
        elseif char == "\\" and quote == '"' and index < #command then
          index = index + 1
          token[#token + 1] = command:sub(index, index)
        else
          token[#token + 1] = char
        end
      elseif char == '"' or char == "'" then
        quote = char
      elseif char:match("%s") then
        break
      elseif char == "\\" and index < #command then
        index = index + 1
        token[#token + 1] = command:sub(index, index)
      else
        token[#token + 1] = char
      end
      index = index + 1
    end
    argv[#argv + 1] = table.concat(token)
    spans[#spans + 1] = { start = start - 1, finish = index - 1 }
  end
  return argv, spans
end

---@param self ajans.cli.Tool
---@param proc ajans.cli.ProcessMatch
---@return {start:integer,finish:integer}[]
local function executable_spans(self, proc)
  local argv, spans = command_tokens(proc)
  local first = basename(argv[1] or proc.executable)
  local runtime = basename(proc.runtime_executable)
  local configured = basename(self.cmd and self.cmd[1])
  if runtime ~= "" and runtime ~= first and not (INTERPRETERS[runtime] and first == configured) then
    return {}
  end
  local allowed = spans[1] and { spans[1] } or {}
  local interpreter = INTERPRETERS[runtime ~= "" and runtime or first]
  if interpreter and spans[2] then
    allowed[#allowed + 1] = spans[2]
  end
  return allowed
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

---@param proc ajans.cli.ProcessMatch
function M:is_proc(proc)
  local is_proc = self.config.is_proc
  if type(is_proc) == "string" then
    local ok, re = pcall(vim.regex, is_proc)
    if ok then
      is_proc = function(tool, p)
        local start, finish = re:match_str(p.cmd or "")
        if start == nil then
          return false
        end
        for _, span in ipairs(executable_spans(tool, p)) do
          if start >= span.start and start < span.finish and finish >= span.finish then
            return true
          end
        end
        return false
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
