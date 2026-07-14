---@module 'luassert'

local Procs = require("ajans.cli.procs")
local Tmux = require("ajans.cli.session.tmux")
local Util = require("ajans.util")

describe("process inventory", function()
  local original_new
  local original_exec

  before_each(function()
    original_new = Procs.new
    original_exec = Util.exec
  end)

  after_each(function()
    Procs.new = original_new
    Util.exec = original_exec
  end)
  it("parses Linux proc identity with spaces in the command name", function()
    local fields = {
      "S",
      "7",
      "42",
      "42",
      "0",
      "42",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "0",
      "12345",
    }
    local pid, ppid, pgid, tpgid, start_time = Procs.parse_proc_stat("42 (agent process) " .. table.concat(fields, " "))

    assert.are.equal(42, pid)
    assert.are.equal(7, ppid)
    assert.are.equal(42, pgid)
    assert.are.equal(42, tpgid)
    assert.are.equal("12345", start_time)
  end)

  it("distinguishes reused process IDs by incarnation", function()
    local original = { pid = 42, start_time = "one", runtime_executable = "/usr/bin/pi" }

    assert.is_true(Procs.same_identity(original, vim.deepcopy(original)))
    assert.is_false(Procs.same_identity(original, { pid = 42, start_time = "two", runtime_executable = "/usr/bin/pi" }))
    assert.is_false(Procs.same_identity(original, { pid = 42, start_time = "one", runtime_executable = "/tmp/pi" }))
  end)

  it("uses procfs when ps is unavailable", function()
    if not vim.uv.fs_stat("/proc/self") then
      return
    end

    local procs = Procs.new({ force_proc = true })
    local current = procs:get(vim.fn.getpid())

    assert.is_true(procs:is_complete())
    assert.is_table(current)
    assert.is_true(type(current.cmd) == "string" and current.cmd ~= "")
  end)

  it("authorizes tmux input through procfs without ps", function()
    if not vim.uv.fs_stat("/proc/self") then
      return
    end
    Procs.new = function()
      return original_new({ force_proc = true })
    end
    local pid = vim.fn.getpid()
    Util.exec = function()
      return { pid .. ":nvim" }
    end
    local session = setmetatable({
      tmux_pid = pid,
      tmux_pane_id = "%1",
      tool = {
        is_proc = function(_, proc)
          return proc.pid == pid
        end,
      },
    }, Tmux)

    assert.is_true(session:accepts_automated_input())
  end)
end)
