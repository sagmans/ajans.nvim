---@alias ajans.test.BddFunction fun(name:string, body:fun())
---@alias ajans.test.HookFunction fun(body:fun())

---@class ajans.test.EqualAssertions
---@field equal fun(expected:any, actual:any, message?:string)
---@field same fun(expected:any, actual:any, message?:string)

---@class ajans.test.NegatedEqualAssertions
---@field equal fun(unexpected:any, actual:any, message?:string)

---@class ajans.test.NoErrorAssertions
---@field errors fun(callback:fun(...):any, ...:any)

---@class ajans.test.Assertions
---@field are ajans.test.EqualAssertions
---@field are_not ajans.test.NegatedEqualAssertions
---@field has_no ajans.test.NoErrorAssertions
---@field is_false fun(value:any, message?:string)
---@field is_function fun(value:any, message?:string)
---@field is_nil fun(value:any, message?:string)
---@field is_not_nil fun(value:any, message?:string)
---@field is_string fun(value:any, message?:string)
---@field is_table fun(value:any, message?:string)
---@field is_true fun(value:any, message?:string)
---@field matches fun(pattern:string, actual:string, init?:integer, plain?:boolean)
---@overload fun(value:any, message?:string):any

---@class ajans.test.Adapter
---@field assert ajans.test.Assertions
---@field describe ajans.test.BddFunction
---@field it ajans.test.BddFunction
---@field before_each ajans.test.HookFunction
---@field after_each ajans.test.HookFunction
local M = {}

local BDD_GLOBALS = { "describe", "it", "before_each", "after_each" }

---@param name string
---@return function|table
local function runtime_global(name)
  local value = rawget(_G, name)
  if type(value) ~= "function" and type(value) ~= "table" then
    error("MiniTest did not install test global `" .. name .. "`", 3)
  end
  return value
end

for _, name in ipairs(BDD_GLOBALS) do
  runtime_global(name)
end

M.assert = setmetatable({}, {
  __index = function(_, key)
    return runtime_global("assert")[key]
  end,
  __call = function(_, ...)
    return runtime_global("assert")(...)
  end,
})

function M.describe(...)
  return runtime_global("describe")(...)
end

function M.it(...)
  return runtime_global("it")(...)
end

function M.before_each(...)
  return runtime_global("before_each")(...)
end

function M.after_each(...)
  return runtime_global("after_each")(...)
end

return M
