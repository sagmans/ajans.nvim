---@module 'luassert'

local State = require("ajans.cli.state")
local Util = require("ajans.util")

describe("cli", function()
  local original_select
  local original_with
  local original_warn
  local original_schedule

  before_each(function()
    original_select = package.loaded["ajans.cli.ui.select"]
    original_with = State.with
    original_warn = Util.warn
    original_schedule = vim.schedule
  end)

  after_each(function()
    package.loaded["ajans.cli.ui.select"] = original_select
    State.with = original_with
    Util.warn = original_warn
    vim.schedule = original_schedule
  end)

  it("refuses automated input after the expected process exits", function()
    local sent = false
    local warning
    State.with = function(callback)
      callback({
        tool = {
          name = "claude",
          format = function()
            error("stale input must not be formatted")
          end,
        },
        session = {
          authorize_automated_input = function(_, done)
            done(false)
          end,
          send = function()
            sent = true
          end,
        },
      })
    end
    Util.warn = function(message)
      warning = message
    end
    vim.schedule = function(callback)
      callback()
    end

    require("ajans.cli").send({ text = { { "repository context" } } })

    assert.is_false(sent)
    assert.matches("Refusing to send", warning)
  end)

  it("selects with an empty default filter", function()
    local selected_opts
    package.loaded["ajans.cli.ui.select"] = {
      select = function(opts)
        selected_opts = opts
      end,
    }

    require("ajans.cli").select()

    assert.are.same({}, selected_opts.filter)
    assert.is_function(selected_opts.cb)
  end)
end)
