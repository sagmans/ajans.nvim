local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Session = require("ajans.cli.session")
local State = require("ajans.cli.state")
local Util = require("ajans.util")

---@class tests.cli.Tool
---@field name string
---@field format fun(self:tests.cli.Tool, text:ajans.Text[]):string

---@class tests.cli.Session
---@field authorize_automated_input fun(self:tests.cli.Session, done:fun(accepted:boolean))
---@field send fun(self:tests.cli.Session, value:string)
---@field submit? fun()

---@class tests.cli.State
---@field tool tests.cli.Tool
---@field session tests.cli.Session

---@class tests.cli.StateApi
---@field with fun(callback:fun(state:tests.cli.State), opts?:ajans.cli.With)
local StateDouble = State --[[@as tests.cli.StateApi]]

describe("cli", function()
  local original_select
  local original_with
  local original_warn
  local original_schedule
  local original_owns

  before_each(function()
    original_select = package.loaded["ajans.cli.ui.select"]
    original_with = StateDouble.with
    original_warn = Util.warn
    original_schedule = vim.schedule
    original_owns = Session.owns
  end)

  after_each(function()
    package.loaded["ajans.cli.ui.select"] = original_select
    StateDouble.with = original_with
    Util.warn = original_warn
    vim.schedule = original_schedule
    Session.owns = original_owns
  end)

  it("refuses automated input after the expected process exits", function()
    local sent = false
    local warning
    StateDouble.with = function(callback)
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
    Session.owns = function()
      return true
    end
    vim.schedule = function(callback)
      callback()
    end

    require("ajans.cli").send({ text = { { { "repository context" } } } })

    assert.is_false(sent)
    assert.matches("Refusing to send", warning)
  end)

  it("cancels accepted input when the session detached during authorization", function()
    local authorization
    local attached = true
    local formatted = false
    local sent = false
    local session = {
      id = "session-1",
      authorize_automated_input = function(_, done)
        authorization = done
      end,
      send = function()
        sent = true
      end,
    }
    StateDouble.with = function(callback)
      callback({
        tool = {
          name = "pi",
          format = function()
            formatted = true
            return "secret"
          end,
        },
        session = session,
      })
    end
    Session.owns = function(candidate)
      return attached and candidate == session
    end
    vim.schedule = function(callback)
      callback()
    end

    require("ajans.cli").send({ text = { { { "repository context" } } } })
    attached = false
    authorization(true)

    assert.is_false(formatted)
    assert.is_false(sent)
  end)

  it("formats, sends, and submits accepted input exactly once", function()
    local authorization
    local formats = 0
    local sends = {}
    local submits = 0
    local session = {
      id = "session-1",
      authorize_automated_input = function(_, done)
        authorization = done
      end,
      send = function(_, value)
        sends[#sends + 1] = value
      end,
      submit = function()
        submits = submits + 1
      end,
    }
    StateDouble.with = function(callback)
      callback({
        tool = {
          name = "pi",
          format = function()
            formats = formats + 1
            return "formatted"
          end,
        },
        session = session,
      })
    end
    Session.owns = function(candidate)
      return candidate == session
    end
    vim.schedule = function(callback)
      callback()
    end

    require("ajans.cli").send({ text = { { { "context" } } }, submit = true })
    assert.are.equal(0, formats)
    authorization(true)

    assert.are.equal(1, formats)
    assert.are.same({ "formatted\n" }, sends)
    assert.are.equal(1, submits)
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
