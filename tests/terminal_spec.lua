local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

describe("terminal", function()
  local original_schedule
  local original_now
  local original_defer
  local original_chan_send
  local original_buf_call
  local original_put
  local original_startinsert
  local original_error

  before_each(function()
    original_schedule = vim.schedule
    original_now = vim.uv.now
    original_defer = vim.defer_fn
    original_chan_send = vim.api.nvim_chan_send
    original_buf_call = vim.api.nvim_buf_call
    original_put = vim.api.nvim_put
    original_startinsert = vim.cmd.startinsert
    original_error = require("ajans.util").error
  end)

  after_each(function()
    vim.schedule = original_schedule
    vim.uv.now = original_now
    vim.defer_fn = original_defer
    vim.api.nvim_chan_send = original_chan_send
    vim.api.nvim_buf_call = original_buf_call
    vim.api.nvim_put = original_put
    vim.cmd.startinsert = original_startinsert
    require("ajans.util").error = original_error
  end)

  it("sends queued input to the terminal job channel", function()
    local Terminal = require("ajans.cli.terminal")
    local sent = {}
    local put_called = false

    vim.schedule = function(cb)
      cb()
    end
    vim.api.nvim_chan_send = function(chan, data)
      sent[#sent + 1] = { chan, data }
    end
    vim.api.nvim_buf_call = function(_, cb)
      cb()
    end
    vim.api.nvim_put = function()
      put_called = true
    end
    vim.cmd.startinsert = function() end

    local terminal = setmetatable({
      job = 42,
      buf = 7,
      send_queue = { "hello\r\n" },
      timer = {
        start = function(_, _, _, cb)
          cb()
        end,
      },
      is_running = function()
        return true
      end,
      is_focused = function()
        return true
      end,
    }, Terminal)

    Terminal.on_ready(terminal)

    assert.are.same({ { 42, "hello\n" } }, sent)
    assert.is_false(put_called)
  end)

  it("revalidates a mux parent when queued input reaches delivery", function()
    local Terminal = require("ajans.cli.terminal")
    local authorization
    local sent = false
    vim.schedule = function(callback)
      callback()
    end
    local terminal = setmetatable({
      job = 42,
      send_queue = { "secret", "\r" },
      timer = {
        start = function(_, _, _, callback)
          callback()
        end,
      },
      parent = {
        send = function()
          sent = true
        end,
        authorize_automated_input = function(_, callback)
          authorization = callback
        end,
      },
      is_running = function()
        return true
      end,
      is_focused = function()
        return false
      end,
    }, Terminal)

    terminal:on_ready()
    assert.is_false(sent)
    authorization(false)
    assert.is_false(sent)
    assert.are.same({}, terminal.send_queue)
  end)

  it("cancels queued delivery when closed during authorization", function()
    local Terminal = require("ajans.cli.terminal")
    local authorization
    local sent = false
    vim.schedule = function(callback)
      callback()
    end
    local terminal = setmetatable({
      job = 42,
      send_queue = { "secret" },
      timer = {
        start = function(_, _, _, callback)
          callback()
        end,
      },
      parent = {
        send = function()
          sent = true
        end,
        authorize_automated_input = function(_, callback)
          authorization = callback
        end,
      },
      is_running = function()
        return true
      end,
      is_focused = function()
        return false
      end,
    }, Terminal)

    terminal:on_ready()
    terminal.closed = true
    authorization(true)

    assert.is_false(sent)
    assert.are.same({}, terminal.send_queue)
    assert.is_false(terminal._sending)
  end)

  it("delivers an accepted Enter exactly once through its mux parent", function()
    local Terminal = require("ajans.cli.terminal")
    local sends = 0
    local submits = 0
    vim.schedule = function(callback)
      callback()
    end
    local terminal = setmetatable({
      job = 42,
      send_queue = { "\r" },
      timer = {
        start = function(_, _, _, callback)
          callback()
        end,
      },
      parent = {
        send = function()
          sends = sends + 1
        end,
        submit = function()
          submits = submits + 1
        end,
        authorize_automated_input = function(_, callback)
          callback(true)
        end,
      },
      is_running = function()
        return true
      end,
      is_focused = function()
        return false
      end,
    }, Terminal)

    terminal:on_ready()

    assert.are.equal(1, submits)
    assert.are.equal(0, sends)
  end)

  it("recovers the input queue when authorization or delivery throws", function()
    local Terminal = require("ajans.cli.terminal")
    local reports = {}
    require("ajans.util").error = function(message)
      reports[#reports + 1] = message
    end
    vim.schedule = function(callback)
      callback()
    end

    for _, failure in ipairs({ "authorization", "delivery" }) do
      local terminal = setmetatable({
        job = 42,
        send_queue = { "secret", "later" },
        timer = {
          start = function(_, _, _, callback)
            callback()
          end,
        },
        parent = {
          send = function()
            if failure == "delivery" then
              error("send failed")
            end
            return true
          end,
          authorize_automated_input = function(_, callback)
            if failure == "authorization" then
              error("authorization failed")
            end
            callback(true)
          end,
        },
        is_running = function()
          return true
        end,
        is_focused = function()
          return false
        end,
      }, Terminal)

      assert.has_no.errors(function()
        terminal:on_ready()
      end)
      assert.is_false(terminal._sending)
      assert.are.same({}, terminal.send_queue)
    end
    assert.are.equal(2, #reports)
  end)

  it("does not restart or queue input after close", function()
    local Terminal = require("ajans.cli.terminal")
    local started = false
    local terminal = setmetatable({
      closed = true,
      send_queue = {},
      start = function()
        started = true
      end,
      is_running = function()
        return false
      end,
    }, Terminal)

    assert.is_false(terminal:send("secret"))
    assert.is_nil(terminal:submit())
    assert.is_false(started)
    assert.are.same({}, terminal.send_queue)
  end)

  it("closes terminal resources when detached", function()
    local Terminal = require("ajans.cli.terminal")
    local closed = false
    local terminal = setmetatable({
      close = function()
        closed = true
      end,
    }, Terminal)

    terminal:detach()

    assert.is_true(closed)
  end)

  it("authorizes a fresh tmux prompt only after resolving the target process", function()
    local Terminal = require("ajans.cli.terminal")
    local expected_process = true
    local pane_checks = 0
    local parent = {
      backend = "tmux",
      pane_id = function(self)
        pane_checks = pane_checks + 1
        if pane_checks > 1 then
          self.tmux_pid = 42
          return "%1"
        end
      end,
      accepts_automated_input = function()
        return expected_process
      end,
    }
    local function fresh_terminal()
      return setmetatable({
        fresh = true,
        parent = parent,
        is_running = function()
          return true
        end,
      }, Terminal)
    end

    local accepted
    local deferred
    vim.uv.now = function()
      return 0
    end
    vim.defer_fn = function(callback)
      deferred = callback
      return 1
    end
    fresh_terminal():authorize_automated_input(function(value)
      accepted = value
    end)
    assert.is_nil(accepted)
    assert.are.equal(1, pane_checks)
    deferred()
    assert.is_true(accepted)
    assert.are.equal(2, pane_checks)

    parent.tmux_pid = nil
    expected_process = false
    vim.defer_fn = original_defer
    local ticks = 0
    vim.uv.now = function()
      ticks = ticks + 1
      return ticks == 1 and 0 or 1000
    end
    fresh_terminal():authorize_automated_input(function(value)
      accepted = value
    end)
    assert.is_false(accepted)
  end)

  it("skips send loop when no timer exists", function()
    local Terminal = require("ajans.cli.terminal")
    local terminal = setmetatable({ timer = nil }, Terminal)

    assert.has_no.errors(function()
      Terminal.on_ready(terminal)
    end)
  end)
end)
