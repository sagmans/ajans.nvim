local Config = require("ajans.config")
local Util = require("ajans.util")

local M = {}

---@class ajans.Picker
---@field open fun(source:string, cb:fun(items:ajans.context.Loc[]), opts?:table)
---@field action fun(cb:fun(items:ajans.context.Loc[])):fun()

---@param picker? string
function M.get(picker)
  local pickers = picker and { picker } or { Config.cli.picker, "snacks", "telescope", "fzf-lua" }
  for _, name in ipairs(pickers) do
    ---@type boolean, ajans.Picker
    local ok, mod = pcall(require, "ajans.cli.picker." .. name)
    if ok and pcall(require, name) then
      return mod
    end
  end
  return Util.error(picker and ("Invalid picker: " .. picker) or "No valid picker found")
end

---@param opts? ajans.context.loc.Opts|ajans.cli.Send
function M.send_cb(opts)
  opts = opts or {}
  local loc_opts = { kind = opts.kind or "file" }
  ---@param items ajans.context.Loc[]
  return function(items)
    local Loc = require("ajans.cli.context.location")
    local ret = { { " " } } ---@type ajans.Text
    for _, item in ipairs(items) do
      local file = Loc.get(item, loc_opts)[1]
      if file then
        vim.list_extend(ret, file)
        ret[#ret + 1] = { " " }
      end
    end
    vim.schedule(function()
      opts = vim.tbl_deep_extend("force", vim.deepcopy(opts or {}), { text = { ret } })
      ---@cast opts ajans.cli.Send
      require("ajans.cli").send(opts)
    end)
  end
end

---@param source string
---@param opts? ajans.context.loc.Opts|ajans.cli.Send
---@param popts? table
function M.open(source, opts, popts)
  local picker = M.get()
  return picker and picker.open(source, M.send_cb(opts), popts)
end

return M
