---@module 'luassert'

local Procs = require("ajans.cli.procs")
local Tmux = require("ajans.cli.session.tmux")

describe("process inventory", function()
  local original_new

  before_each(function()
    original_new = Procs.new
  end)

  after_each(function()
    Procs.new = original_new
  end)
  it("parses Linux proc stat records with spaces in the command name", function()
    local pid, ppid = Procs.parse_proc_stat("42 (agent process) S 7 42 42 0")

    assert.are.equal(42, pid)
    assert.are.equal(7, ppid)
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
    local session = setmetatable({
      tmux_pid = pid,
      tool = {
        is_proc = function(_, proc)
          return proc.pid == pid
        end,
      },
    }, Tmux)

    assert.is_true(session:accepts_automated_input())
  end)
end)
