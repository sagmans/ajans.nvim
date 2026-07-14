local Util = require("ajans.util")

local M = {}

---@alias ajans.Pos [integer, integer]
---@alias ajans.Chunk { [1]:string, [2]?:(string|string[])}
---@alias ajans.Text ajans.Chunk[]

---@class ajans.Extmark: vim.api.keyset.set_extmark
---@field row integer
---@field col integer

---@param text ajans.Text
---@param from? integer
---@param to? integer
function M.sub(text, from, to)
  local ret = {} ---@type ajans.Text
  local pos = 1
  from = from or 1
  to = to or math.huge

  for _, chunk in ipairs(text) do
    local width = Util.width(chunk[1])
    local end_pos = pos + width - 1
    local start_i = math.max(from, pos)
    local end_i = math.min(to, end_pos)

    if pos >= from and end_pos <= to then
      ret[#ret + 1] = chunk
    elseif start_i <= end_i then
      local sub_width = end_i - start_i + 1
      local offset = start_i - pos
      local sub_str = vim.fn.strcharpart(chunk[1], offset, sub_width)
      ret[#ret + 1] = { sub_str, chunk[2] }
    end

    if end_pos >= to then
      break
    end
    pos = end_pos + 1
  end
  return ret
end

---@param virt_lines ajans.Text[]
function M.fix_indent(virt_lines)
  local ts = vim.o.tabstop
  local indent = -1
  for _, vt in ipairs(virt_lines) do
    local chunk = vt[1]
    if chunk then
      -- normalize tabs
      chunk[1] = chunk[1]:gsub("\t", string.rep(" ", ts))
      local ws = chunk[1]:match("^%s*") ---@type string?
      if ws then
        indent = indent == -1 and #ws or math.min(indent, #ws)
      end
    end
  end
  ---@param t ajans.Text
  return indent <= 0 and virt_lines or vim.tbl_map(function(t)
    return M.sub(t, indent + 1)
  end, virt_lines)
end

---@param virt_lines ajans.Text[]
---@return string[]
function M.lines(virt_lines)
  ---@param vt ajans.Text
  return vim.tbl_map(function(vt)
    return table.concat(vim.tbl_map(function(c)
      return type(c[1]) == "string" and c[1] or ""
    end, vt))
  end, virt_lines)
end

---@param vt ajans.Text
---@return integer
function M.width(vt)
  local ret = 0
  for _, chunk in ipairs(vt) do
    ret = ret + Util.width(chunk[1])
  end
  return ret
end

---@param vl ajans.Text[]
function M.lines_width(vl)
  local ret = 0
  for _, vt in ipairs(vl) do
    ret = math.max(ret, M.width(vt))
  end
  return ret
end

---@param data ajans.context.Fn.ret
---@return ajans.Text[]
function M.to_text(data)
  if type(data) == "string" then
    if data == "" then
      return {}
    end
    return M.to_text(vim.split(data, "\n", { plain = true }))
  end

  ---@cast data string[]|ajans.Text|ajans.Text[]
  if #data == 0 then
    return {}
  end

  if type(data[1]) == "string" then
    ---@cast data string[]
    return vim.tbl_map(function(s)
      return { { s } }
    end, data)
  end

  ---@cast data ajans.Text|ajans.Text[]
  if type(vim.tbl_get(data, 1, 1)) == "string" then
    ---@cast data ajans.Text
    return { data }
  end

  return data
end

--- Split a str by a pattern, keeping the pattern matches
---@param str string
function M.split(str, pattern)
  local ret = {} ---@type string[]
  local pos = 1
  while pos <= #str do
    local from, to, key = str:find("(" .. pattern .. ")", pos)
    if from and to and key then
      if from > pos then
        ret[#ret + 1] = str:sub(pos, from - 1)
      end
      ret[#ret + 1] = key
      pos = to + 1
    else
      break
    end
  end
  if pos <= #str then
    ret[#ret + 1] = str:sub(pos)
  end
  return ret
end

---@param text ajans.Text[]
---@param cb fun(str:string, chunk:ajans.Chunk):string?, integer?
---@param filter? string[]|string hl to filter by
function M.transform(text, cb, filter)
  filter = (filter and type(filter) == "string") and { filter } or filter
  ---@cast filter string[]?

  ---@param chunk ajans.Chunk
  local function want(chunk)
    if not filter then
      return true
    end
    local hl = type(chunk[2]) == "string" and { chunk[2] } or chunk[2] or {}
    ---@cast hl string[]
    for _, f in ipairs(filter) do
      if vim.tbl_contains(hl, f) then
        return true
      end
    end
  end

  for _, line in ipairs(text) do
    for _, t in ipairs(line) do
      if want(t) then
        t[1] = cb(t[1], t) or t[1]
      end
    end
  end
end

---@param text ajans.Text[]
function M.to_string(text)
  return table.concat(M.lines(text), "\n")
end

return M
