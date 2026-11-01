local Config = require("ajans.config")
local Util = require("ajans.util")

---@class ajans.cli.Select: ajans.cli.With
---@field cb fun(state?:ajans.cli.State)
---@field auto? boolean Automatically select if only one tool matches the filter

local M = {}

---@param opts ajans.cli.Select
function M.select(opts)
  assert(type(opts) == "table", "opts must be a table")
  assert(type(opts.cb) == "function", "opts.cb must be a function")
  assert(opts.filter ~= nil, "opts.filter is required")
  local tools = require("ajans.cli.state").get(opts.filter)

  ---@param state? ajans.cli.State
  local on_select = function(state)
    if state and not state.installed then
      M.on_missing(state.tool)
      state = nil
    end
    opts.cb(state)
  end

  if #tools == 0 then
    Util.warn("No tools match the given filter")
    return
  elseif #tools == 1 and opts.auto then
    on_select(tools[1])
    return
  end

  ---@type snacks.picker.ui_select.Opts
  local select_opts = {
    prompt = "Select CLI tool:",
    kind = "ajans_cli",
    ---@param tool ajans.cli.State
    format_item = function(tool)
      local parts = M.format(tool)
      return table.concat(vim.tbl_map(function(p)
        return p[1]
      end, parts))
    end,
    snacks = { format = M.format },
  }

  vim.ui.select(tools, select_opts, on_select)
end

---@param tool ajans.cli.Tool
function M.on_missing(tool)
  Util.error(("Tool `%s` is not installed"):format(tool.name))
  if tool.url then
    local ok, err = vim.ui.open(tool.url)
    if ok then
      Util.info(("Opening %s in your browser..."):format(tool.url))
    else
      Util.error(("Failed to open %s: %s"):format(tool.url, err))
    end
  end
end

---@param state ajans.cli.State|snacks.picker.Item
---@param picker? snacks.Picker
function M.format(state, picker)
  local sw = vim.api.nvim_strwidth
  local ret = {} ---@type snacks.picker.Highlight[]

  local status = state.attached and "attached"
    or state.started and "started"
    or state.installed and "installed"
    or "missing"

  local status_hl = "AjansCli" .. status:gsub("^%l", string.upper)

  if picker then
    local count = picker:count()
    local idx = tostring(state.idx)
    idx = (" "):rep(#tostring(count) - #idx) .. idx
    ret[#ret + 1] = { idx .. ".", "SnacksPickerIdx" }
    ret[#ret + 1] = { " " }
  end
  ret[#ret + 1] = { Config.ui.icons[status], status_hl }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { state.tool.name }
  local len = sw(state.tool.name) + 2
  if state.session then
    ret[#ret + 1] = { string.rep(" ", 12 - len) }

    if state.external then
      ret[#ret + 1] = { Config.ui.icons["external_" .. status], status_hl }
    else
      ret[#ret + 1] = { Config.ui.icons["terminal_" .. status], status_hl }
    end

    -- Keep this for debugging purposes
    -- ret[#ret + 1] = { table.concat(state.session.pids or {}, ",") }

    local backends = {} ---@type string[]
    backends[#backends + 1] = state.session.mux_backend or state.session.backend
    if state.external then
      backends[#backends + 1] = state.session.mux_session
    end
    local backend = ("[%s]"):format(table.concat(backends, ":"))

    ret[#ret + 1] = { backend, "Special" }
    len = 12 + sw(backend)
    ret[#ret + 1] = { string.rep(" ", 40 - len) }
    if picker then
      local item = setmetatable({}, { __index = state }) --[[@as snacks.picker.Item]]
      item.file = state.session.cwd
      item.dir = true
      vim.list_extend(ret, require("snacks").picker.format.filename(item, picker))
    else
      ret[#ret + 1] = { vim.fn.fnamemodify(state.session.cwd, ":p:~"), "Directory" }
    end
  end
  return ret
end

return M
