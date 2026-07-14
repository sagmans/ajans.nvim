---@module 'luassert'

local Layout = require("ajans.cli.session.herdr.layout")

local function nested_layout()
  return {
    panes = {
      { pane_id = "sibling", rect = { x = 0, y = 0, width = 25, height = 40 } },
      { pane_id = "new", rect = { x = 25, y = 0, width = 25, height = 40 } },
      { pane_id = "outer-sibling", rect = { x = 50, y = 0, width = 50, height = 40 } },
    },
    splits = {
      { id = "outer", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
      { id = "immediate", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 50, height = 40 } },
    },
  }
end

describe("Herdr layout", function()
  it("selects the smallest split containing a pane", function()
    local layout = nested_layout()

    local split = Layout.containing_split(layout, "new", "right")

    assert.are.equal("immediate", split.id)
  end)

  it("uses a sibling when the requested pane would resize an outer boundary", function()
    local layout = nested_layout()

    local target = Layout.resize_target(layout, "immediate", "new", "right")

    assert.are.equal("sibling", target)
  end)

  it("calculates first and second child shares independently at equal ratios", function()
    local layout = nested_layout()
    local split = Layout.split(layout, "immediate")

    assert.is_false(Layout.is_second(split, Layout.pane(layout, "sibling")))
    assert.is_true(Layout.is_second(split, Layout.pane(layout, "new")))
    assert.are.equal(0.5, Layout.share(split, Layout.pane(layout, "sibling")))
    assert.are.equal(0.5, Layout.share(split, Layout.pane(layout, "new")))
  end)

  for _, case in ipairs({
    { name = "missing collections", layout = {} },
    {
      name = "missing pane rect",
      layout = { panes = { { pane_id = "new" } }, splits = {} },
    },
    {
      name = "non-finite pane geometry",
      layout = {
        panes = { { pane_id = "new", rect = { x = 0 / 0, y = 0, width = 10, height = 10 } } },
        splits = {},
      },
    },
    {
      name = "missing split identity",
      layout = {
        panes = { { pane_id = "new", rect = { x = 0, y = 0, width = 10, height = 10 } } },
        splits = { { direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 20, height = 10 } } },
      },
    },
    {
      name = "invalid split ratio",
      layout = {
        panes = { { pane_id = "new", rect = { x = 0, y = 0, width = 10, height = 10 } } },
        splits = {
          { id = "split", direction = "right", ratio = 2, rect = { x = 0, y = 0, width = 20, height = 10 } },
        },
      },
    },
  }) do
    it("rejects " .. case.name, function()
      local valid, err = Layout.validate(case.layout)

      assert.is_false(valid)
      assert.is_string(err)
    end)
  end
end)
