---@module 'luassert'

local Procs = require("ajans.cli.procs")
local Tmux = require("ajans.cli.session.tmux")
local Util = require("ajans.util")

local PROC_ROOT = "/fixture/proc"

local function proc_stat(pid, ppid, pgid, tpgid, start_time)
  local fields = {
    "S",
    tostring(ppid),
    tostring(pgid),
    tostring(pgid),
    "0",
    tostring(tpgid),
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
    tostring(start_time),
  }
  return ("%d (fixture process) %s"):format(pid, table.concat(fields, " "))
end

local function stub_procfs(pid, command)
  Procs._fs_dir = function(path)
    assert.are.equal(PROC_ROOT, path)
    local returned = false
    return function()
      if not returned then
        returned = true
        return tostring(pid), "directory"
      end
    end
  end
  Procs._read_file = function(path)
    local suffix = path:match("/([^/]+)$")
    if suffix == "stat" then
      return proc_stat(pid, 1, pid, pid, 12345)
    elseif suffix == "cmdline" then
      return command .. "\0"
    elseif suffix == "comm" then
      return command .. "\n"
    end
  end
  Procs._fs_readlink = function()
    return "/usr/bin/" .. command
  end
end

describe("process inventory", function()
  local original_new
  local original_exec
  local original_fs_dir
  local original_read_file
  local original_fs_readlink

  before_each(function()
    original_new = Procs.new
    original_exec = Util.exec
    original_fs_dir = Procs._fs_dir
    original_read_file = Procs._read_file
    original_fs_readlink = Procs._fs_readlink
  end)

  after_each(function()
    Procs.new = original_new
    Util.exec = original_exec
    Procs._fs_dir = original_fs_dir
    Procs._read_file = original_read_file
    Procs._fs_readlink = original_fs_readlink
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

  it("uses procfs fixtures on every platform", function()
    stub_procfs(42, "fixture-agent")

    local procs = Procs.new({ force_proc = true, proc_root = PROC_ROOT })
    local current = procs:get(42)

    assert.is_true(procs:is_complete())
    assert.is_table(current)
    assert.are.equal("fixture-agent", current.cmd)
    assert.are.equal("12345", current.start_time)
    assert.are.equal(42, current.pgid)
    assert.are.equal(42, current.tpgid)
    assert.are.equal("/usr/bin/fixture-agent", current.runtime_executable)
  end)

  it("authorizes tmux input through procfs fixtures", function()
    local pid = 42
    stub_procfs(pid, "nvim")
    Procs.new = function()
      return original_new({ force_proc = true, proc_root = PROC_ROOT })
    end
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
