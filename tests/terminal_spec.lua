---@module 'luassert'

describe("terminal", function()
  local original_schedule
  local original_chan_send
  local original_buf_call
  local original_put
  local original_startinsert

  before_each(function()
    original_schedule = vim.schedule
    original_chan_send = vim.api.nvim_chan_send
    original_buf_call = vim.api.nvim_buf_call
    original_put = vim.api.nvim_put
    original_startinsert = vim.cmd.startinsert
  end)

  after_each(function()
    vim.schedule = original_schedule
    vim.api.nvim_chan_send = original_chan_send
    vim.api.nvim_buf_call = original_buf_call
    vim.api.nvim_put = original_put
    vim.cmd.startinsert = original_startinsert
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

  it("accepts the initial prompt while fresh tmux discovery catches up", function()
    local Terminal = require("ajans.cli.terminal")
    local parent_checks = 0
    local terminal = setmetatable({
      fresh = true,
      parent = {
        backend = "tmux",
        accepts_automated_input = function()
          parent_checks = parent_checks + 1
          return false
        end,
      },
      is_running = function()
        return true
      end,
    }, Terminal)

    assert.is_true(terminal:accepts_automated_input())
    assert.are.equal(0, parent_checks)
    terminal.parent.tmux_pid = 42
    assert.is_false(terminal:accepts_automated_input())
    assert.are.equal(1, parent_checks)
  end)

  it("skips send loop when no timer exists", function()
    local Terminal = require("ajans.cli.terminal")
    local terminal = setmetatable({ timer = nil }, Terminal)

    assert.has_no.errors(function()
      Terminal.on_ready(terminal)
    end)
  end)
end)
