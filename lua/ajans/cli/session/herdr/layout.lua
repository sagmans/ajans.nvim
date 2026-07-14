local M = {}

local DIRECTIONS = { right = true, down = true }
local NAV_ORIENTATION = { left = "right", right = "right", up = "down", down = "down" }
local OPPOSITE = { left = "right", right = "left", up = "down", down = "up" }

---@param value any
---@return boolean
local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

---@param rect any
---@return boolean
local function valid_rect(rect)
  return type(rect) == "table"
    and finite(rect.x)
    and finite(rect.y)
    and finite(rect.width)
    and finite(rect.height)
    and rect.x >= 0
    and rect.y >= 0
    and rect.width > 0
    and rect.height > 0
end

---@param layout any
---@return boolean, string?
function M.validate(layout)
  if type(layout) ~= "table" or type(layout.panes) ~= "table" or type(layout.splits) ~= "table" then
    return false, "layout is missing pane or split collections"
  end
  for _, pane in ipairs(layout.panes) do
    if type(pane) ~= "table" or type(pane.pane_id) ~= "string" or not valid_rect(pane.rect) then
      return false, "layout contains a pane with invalid identity or geometry"
    end
  end
  for _, split in ipairs(layout.splits) do
    if
      type(split) ~= "table"
      or type(split.id) ~= "string"
      or not DIRECTIONS[split.direction]
      or not finite(split.ratio)
      or split.ratio < 0.1
      or split.ratio > 0.9
      or not valid_rect(split.rect)
    then
      return false, "layout contains a split with invalid identity, direction, ratio, or geometry"
    end
  end
  return true
end

---@param layout table
---@param pane_id string
---@return table?
function M.pane(layout, pane_id)
  for _, pane in ipairs(layout.panes) do
    if pane.pane_id == pane_id then
      return pane
    end
  end
end

---@param layout table
---@param split_id string
---@return table?
function M.split(layout, split_id)
  for _, split in ipairs(layout.splits) do
    if split.id == split_id then
      return split
    end
  end
end

---@param outer table
---@param inner table
---@return boolean
local function contains(outer, inner)
  return inner.x >= outer.x
    and inner.y >= outer.y
    and inner.x + inner.width <= outer.x + outer.width
    and inner.y + inner.height <= outer.y + outer.height
end

---@param layout table
---@param pane_id string
---@param direction "right"|"down"
---@return table?
function M.containing_split(layout, pane_id, direction)
  local pane = M.pane(layout, pane_id)
  if not pane then
    return
  end
  local best
  local best_area
  for _, split in ipairs(layout.splits) do
    if split.direction == direction and contains(split.rect, pane.rect) then
      local area = split.rect.width * split.rect.height
      if not best_area or area < best_area then
        best = split
        best_area = area
      end
    end
  end
  return best
end

---@param split table
---@return number
local function position(split)
  local dimension = split.direction == "right" and split.rect.width or split.rect.height
  local offset = math.floor(dimension * split.ratio + 0.5)
  return (split.direction == "right" and split.rect.x or split.rect.y) + offset
end

---@param start_a number
---@param length_a number
---@param start_b number
---@param length_b number
---@return boolean
local function overlaps(start_a, length_a, start_b, length_b)
  return start_a < start_b + length_b and start_a + length_a > start_b
end

---@param split table
---@param pane table
---@param nav "left"|"right"|"up"|"down"
---@return number
local function distance(split, pane, nav)
  local edge
  if nav == "left" then
    edge = pane.rect.x
  elseif nav == "right" then
    edge = pane.rect.x + pane.rect.width
  elseif nav == "up" then
    edge = pane.rect.y
  else
    edge = pane.rect.y + pane.rect.height
  end
  return math.abs(position(split) - edge)
end

---@param split table
---@param pane table
---@param nav "left"|"right"|"up"|"down"
---@return boolean
local function crosses(split, pane, nav)
  if nav == "left" or nav == "right" then
    return overlaps(split.rect.y, split.rect.height, pane.rect.y, pane.rect.height)
  end
  return overlaps(split.rect.x, split.rect.width, pane.rect.x, pane.rect.width)
end

---@param layout table
---@param pane table
---@param nav "left"|"right"|"up"|"down"
---@return table?
local function targeted_split(layout, pane, nav)
  local function nearest(direction)
    local best
    local best_distance
    for _, split in ipairs(layout.splits) do
      if split.direction == NAV_ORIENTATION[nav] and crosses(split, pane, nav) then
        local found = distance(split, pane, direction)
        if found <= 1 and (not best_distance or found < best_distance) then
          best = split
          best_distance = found
        end
      end
    end
    return best
  end
  return nearest(nav) or nearest(OPPOSITE[nav])
end

---@param layout table
---@param split_id string
---@param preferred_pane_id string
---@param nav "left"|"right"|"up"|"down"
---@return string?
function M.resize_target(layout, split_id, preferred_pane_id, nav)
  local preferred = M.pane(layout, preferred_pane_id)
  if preferred then
    local targeted = targeted_split(layout, preferred, nav)
    if targeted and targeted.id == split_id then
      return preferred.pane_id
    end
  end
  for _, pane in ipairs(layout.panes) do
    local targeted = targeted_split(layout, pane, nav)
    if targeted and targeted.id == split_id then
      return pane.pane_id
    end
  end
end

---@param split table
---@param pane table
---@return boolean
function M.is_second(split, pane)
  return split.direction == "right" and pane.rect.x >= position(split) - 1
    or split.direction == "down" and pane.rect.y >= position(split) - 1
end

---@param split table
---@param pane table
---@return number
function M.share(split, pane)
  return M.is_second(split, pane) and 1 - split.ratio or split.ratio
end

return M
