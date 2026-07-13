---@module 'luassert'

describe("terminal", function()
  local original_schedule
  local original_now
  local original_chan_send
  local original_buf_call
  local original_put
  local original_startinsert

  before_each(function()
    original_schedule = vim.schedule
    original_now = vim.uv.now
    original_chan_send = vim.api.nvim_chan_send
    original_buf_call = vim.api.nvim_buf_call
    original_put = vim.api.nvim_put
    original_startinsert = vim.cmd.startinsert
  end)

  after_each(function()
    vim.schedule = original_schedule
    vim.uv.now = original_now
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

  it("authorizes a fresh tmux prompt only after resolving the target process", function()
    local Terminal = require("ajans.cli.terminal")
    local expected_process = true
    local parent = {
      backend = "tmux",
      pane_id = function(self)
        self.tmux_pid = 42
        return "%1"
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
    fresh_terminal():authorize_automated_input(function(value)
      accepted = value
    end)
    assert.is_true(accepted)

    parent.tmux_pid = nil
    expected_process = false
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
