local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it

local Util = require("ajans.util")

describe("util notify", function()
  it("routes to vim.notify with title", function()
    local called = {}
    local original_schedule = vim.schedule
    local original_notify = vim.notify

    vim.schedule = function(cb)
      cb()
    end
    vim.notify = function(msg, level, opts)
      table.insert(called, { msg = msg, level = level, opts = opts })
    end

    Util.error("oops")
    Util.info("hello")

    vim.schedule = original_schedule
    vim.notify = original_notify

    assert.are.same({
      { msg = "oops", level = vim.log.levels.ERROR, opts = { title = "Ajans" } },
      { msg = "hello", level = vim.log.levels.INFO, opts = { title = "Ajans" } },
    }, called)
  end)
end)
