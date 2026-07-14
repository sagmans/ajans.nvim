local M = {}

---@alias ajans.textobject.Range6 [integer, integer, integer, integer, integer, integer]

---@class ajans.textobject.Opts
---@field type "function"|"class"|"block"|"parameter"|"comment"|"call"|"conditional"|"loop"|"assignment"|"return"|"number"
---@field kind? "position"|"code" position: returns location, code: returns highlighted code (default: "position")
---@field inner? boolean Use inner textobject instead of outer (default: false)

---Check if nvim-treesitter-textobjects is available
---@return boolean
local function has_textobjects()
  return pcall(require, "nvim-treesitter-textobjects.shared")
end

---Get textobject range using nvim-treesitter-textobjects
---@param buf integer
---@param row integer (1-based)
---@param col integer (1-based)
---@param textobject string e.g. "function", "class", "block"
---@param inner boolean
---@return ajans.textobject.Range6?
local function get_textobject_range(buf, row, col, textobject, inner)
  if not has_textobjects() then
    return nil
  end

  -- Get the treesitter parser and ensure it's parsed
  local ok_parser, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok_parser or not parser then
    return nil
  end

  parser:parse()
  local lang = parser:lang()

  -- Check if the query exists for this language
  local ts_query = vim.treesitter.query.get(lang, "textobjects")
  if not ts_query then
    return nil
  end

  local ok, shared = pcall(require, "nvim-treesitter-textobjects.shared")
  if not ok then
    return nil
  end

  local query_string = inner and ("@%s.inner"):format(textobject) or ("@%s.outer"):format(textobject)

  -- textobject_at_point expects 1-based position
  -- Wrap in pcall to handle errors gracefully (e.g., unsupported filetype)
  local success, range = pcall(shared.textobject_at_point, query_string, "textobjects", buf, { row, col })
  if not success then
    return nil
  end

  return range
end

---Get the name of a textobject node
---@param buf integer
---@param start_row integer (0-based)
---@param start_col integer (0-based)
---@return string?
local function get_textobject_name(buf, start_row, start_col)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return nil
  end

  parser:parse()

  local node = vim.treesitter.get_node({
    bufnr = buf,
    pos = { start_row, start_col },
  })

  if not node then
    return nil
  end

  -- Common patterns for finding the name of a function/class
  local name_fields = { "name", "identifier", "field" }

  for _, field in ipairs(name_fields) do
    local name_node = node:field(field)[1]
    if name_node then
      local name_text = vim.treesitter.get_node_text(name_node, buf)
      if name_text and #name_text > 0 then
        return name_text
      end
    end
  end

  -- Try to find identifier as child
  for child in node:iter_children() do
    if child:type():match("identifier") then
      local name_text = vim.treesitter.get_node_text(child, buf)
      if name_text and #name_text > 0 then
        return name_text
      end
    end
  end

  return nil
end

---Get the textobject (function/class/etc) at the current cursor position
---@param ctx ajans.context.ctx
---@param opts? ajans.textobject.Opts
---@return ajans.Text[]?
function M.get(ctx, opts)
  opts = opts or {}
  opts.type = opts.type or "function"
  opts.kind = opts.kind or "position"
  opts.inner = opts.inner or false

  local buf = ctx.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- Get the textobject range using nvim-treesitter-textobjects
  local range = get_textobject_range(buf, ctx.row, ctx.col, opts.type, opts.inner)
  if not range then
    return nil
  end

  -- Range6 format: [start_row, start_col, start_byte, end_row, end_col, end_byte]
  -- All values are 0-based
  local start_row, start_col, _, end_row = unpack(range)

  -- If kind is "position", return location info with node name
  if opts.kind == "position" then
    local name = get_textobject_name(buf, start_row, start_col)
    local Loc = require("ajans.cli.context.location")

    -- Create a synthetic context for the node's position
    local node_ctx = {
      buf = buf,
      cwd = ctx.cwd,
      row = start_row + 1, -- Convert back to 1-based
      col = start_col + 1,
      name = vim.api.nvim_buf_get_name(buf),
    }

    -- Get the location text
    local loc_text = Loc.get(node_ctx, { kind = "position" })
    if not loc_text or #loc_text == 0 then
      return nil
    end

    -- Prepend the node type and name
    local ret = {} ---@type ajans.Text
    ret[#ret + 1] = { opts.type, "Type" }
    if name then
      ret[#ret + 1] = { " ", "Normal" }
      ret[#ret + 1] = { name, "Function" }
    end
    ret[#ret + 1] = { " ", "Normal" }

    -- Add the location parts
    for _, chunk in ipairs(loc_text[1]) do
      ret[#ret + 1] = chunk
    end

    return { ret }
  end

  -- kind == "code": return syntax-highlighted code
  local TS = require("ajans.treesitter")
  local virt_lines = TS.get_virtual_lines(buf, {
    ft = vim.bo[buf].filetype,
    start_row = start_row,
    end_row = end_row + 1,
  })

  -- Fix indentation
  local Text = require("ajans.text")
  virt_lines = Text.fix_indent(virt_lines)

  return virt_lines
end

return M
