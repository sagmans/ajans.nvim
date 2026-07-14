local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Select = require("ajans.cli.ui.select")

---@class tests.picker.Tool
---@field name string

---@class tests.picker.Session
---@field cwd string
---@field backend string
---@field mux_backend? string
---@field mux_session? string

---@class tests.picker.State
---@field idx? integer
---@field installed? boolean
---@field started? boolean
---@field external? boolean
---@field tool tests.picker.Tool
---@field session? tests.picker.Session

---@class tests.picker.Picker
---@field count fun(self:tests.picker.Picker):integer

---@class tests.picker.SelectApi
---@field format fun(state:tests.picker.State, picker?:tests.picker.Picker):snacks.picker.Highlight[]
---@field select fun(opts:{filter:ajans.cli.Filter})
local SelectDouble = Select --[[@as tests.picker.SelectApi]]

describe("cli picker", function()
  local original_snacks
  local original_snacks_picker
  local original_telescope_actions
  local original_telescope_state
  local original_snacks_picker_util
  local original_global_snacks

  before_each(function()
    original_snacks = package.loaded.snacks
    original_snacks_picker = package.loaded["ajans.cli.picker.snacks"]
    original_telescope_actions = package.loaded["telescope.actions"]
    original_telescope_state = package.loaded["telescope.actions.state"]
    original_snacks_picker_util = package.loaded["snacks.picker.util"]
    original_global_snacks = _G.Snacks
  end)

  after_each(function()
    package.loaded.snacks = original_snacks
    package.loaded["ajans.cli.picker.snacks"] = original_snacks_picker
    package.loaded["telescope.actions"] = original_telescope_actions
    package.loaded["telescope.actions.state"] = original_telescope_state
    package.loaded["snacks.picker.util"] = original_snacks_picker_util
    _G.Snacks = original_global_snacks
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("falls back when configured picker module is unavailable", function()
    local Config = require("ajans.config")
    local Picker = require("ajans.cli.picker")
    local fake = { open = function() end }

    package.loaded["ajans.cli.picker.snacks"] = fake
    package.loaded.snacks = {}
    Config.setup({ cli = { picker = "missing-picker" } })

    assert.are.equal(fake, Picker.get())
  end)

  it("formats snacks picker items through state fallback", function()
    package.loaded.snacks = {
      picker = {
        format = {
          filename = function(item)
            assert.are.equal("claude", item.tool.name)
            return { { item.file, "Directory" } }
          end,
        },
      },
    }

    local ret = SelectDouble.format({
      idx = 1,
      installed = true,
      tool = { name = "claude" },
      session = { cwd = "/tmp/project", backend = "tmux" },
    }, {
      count = function()
        return 1
      end,
    })

    assert.are.equal("/tmp/project", ret[#ret][1])
  end)

  for _, case in ipairs({
    {
      name = "Herdr terminal wrapper",
      state = {
        installed = true,
        started = true,
        tool = { name = "claude" },
        session = { cwd = "/tmp/project", backend = "terminal", mux_backend = "herdr" },
      },
      expected = "[herdr]",
    },
    {
      name = "external Herdr workspace",
      state = {
        installed = true,
        started = true,
        external = true,
        tool = { name = "claude" },
        session = { cwd = "/tmp/project", backend = "herdr", mux_session = "w1" },
      },
      expected = "[herdr:w1]",
    },
  }) do
    it("formats " .. case.name .. " identity", function()
      local parts = SelectDouble.format(case.state)
      local text = table.concat(vim.tbl_map(function(part)
        return part[1]
      end, parts))

      assert.matches(case.expected, text, nil, true)
    end)
  end

  it("keeps the required Snacks confirm callback", function()
    local SnacksPicker = require("ajans.cli.picker.snacks")
    local confirm
    local called = false
    package.loaded["snacks.picker.util"] = {
      path = function(item)
        return item.name
      end,
    }
    rawset(_G, "Snacks", {
      picker = {
        pick = function(_, opts)
          confirm = opts.confirm
        end,
      },
    })

    SnacksPicker.open("files", function()
      called = true
    end, {
      confirm = function()
        error("caller confirm should not replace Ajans callback")
      end,
    })

    confirm({
      selected = function()
        return { { name = "file.lua" } }
      end,
      close = function() end,
    })

    assert.is_true(called)
  end)

  it("validates required select options", function()
    local ok, err = pcall(function()
      SelectDouble.select({ filter = {} })
    end)

    assert.is_false(ok)
    assert.matches("opts.cb must be a function", tostring(err))
  end)

  it("ignores empty Telescope selections", function()
    local Telescope = require("ajans.cli.picker.telescope")
    package.loaded["telescope.actions"] = { close = function() end }
    package.loaded["telescope.actions.state"] = {
      get_current_picker = function()
        return {
          get_multi_selection = function()
            return {}
          end,
        }
      end,
      get_selected_entry = function()
        return nil
      end,
    }

    local called = false
    Telescope.action(function()
      called = true
    end)(1)

    assert.is_false(called)
  end)
end)
