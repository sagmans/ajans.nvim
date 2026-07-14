local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

describe("file watcher", function()
  local original_new_fs_event
  local original_refresh
  local original_watches
  local original_changes

  before_each(function()
    local Watch = require("ajans.cli.watch")
    original_new_fs_event = vim.uv.new_fs_event
    original_refresh = Watch.refresh
    original_watches = Watch.watches
    original_changes = Watch.changes
  end)

  after_each(function()
    local Watch = require("ajans.cli.watch")
    vim.uv.new_fs_event = original_new_fs_event
    Watch.refresh = original_refresh
    Watch.watches = original_watches
    Watch.changes = original_changes
  end)

  it("joins changed paths and shields refresh errors", function()
    local Watch = require("ajans.cli.watch")
    local callbacks = {}
    vim.uv.new_fs_event = function()
      return {
        start = function(_, _, _, cb)
          callbacks[#callbacks + 1] = cb
          return true
        end,
      }
    end
    Watch.watches = {}
    Watch.changes = {}
    Watch.refresh = function()
      error("refresh failed")
    end

    Watch.start("/tmp/project")

    assert.has_no.errors(function()
      callbacks[1](nil, "dir/file.lua")
    end)
    assert.is_true(Watch.changes[vim.fs.joinpath("/tmp/project", "dir/file.lua")])
  end)
end)
