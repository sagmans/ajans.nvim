local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Config = require("ajans.config")

describe("cli tool runtime configs", function()
  before_each(function()
    package.loaded["ajans.cli.tool"] = nil
  end)

  after_each(function()
    package.loaded["ajans.cli.tool"] = nil
  end)

  it("loads every bundled tool config from aj runtime path", function()
    local Tool = require("ajans.cli.tool")
    local process_cmds = {
      amazon_q = "chat_cli",
      copilot = "copilot --banner",
    }
    local runtime_files = vim.api.nvim_get_runtime_file("aj/cli/*.lua", true)
    local runtime_tools = {}

    for _, file in ipairs(runtime_files) do
      local name = vim.fs.basename(file):gsub("%.lua$", "")
      runtime_tools[name] = file
      assert.is_table(Config.cli.tools[name], name)
    end

    for name in pairs(runtime_tools) do
      local tool = Tool.get(name)

      assert.is_string(runtime_tools[name], name)
      assert.is_table(tool.cmd, name)
      assert.is_string(tool.cmd[1], name)
      assert.is_true(#tool.cmd[1] > 0, name)
      assert.is_not_nil(tool.config.is_proc, name)
      assert.is_true(tool:is_proc({ cmd = process_cmds[name] or tool.cmd[1] }), name)
    end
  end)

  it("matches bundled tool processes by executable name", function()
    local tool = require("ajans.cli.tool").get("claude")

    assert.is_true(tool:is_proc({ cmd = "/opt/bin/claude --banner", executable = "claude" }))
    assert.is_false(tool:is_proc({ cmd = "/usr/bin/cat - claude", executable = "cat" }))
    assert.is_false(tool:is_proc({ cmd = "/opt/bin/claude-helper", executable = "claude-helper" }))
    assert.is_false(tool:is_proc({ cmd = "claude", executable = "claude", runtime_executable = "evil" }))
  end)

  it("matches interpreter scripts and executable-anchored arguments", function()
    local Tool = require("ajans.cli.tool")
    local interpreted = Tool.get("pi")
    local command_sensitive = setmetatable({
      cmd = { "custom" },
      config = { is_proc = "\\<custom\\>.*--agent-mode" },
    }, Tool)

    assert.is_true(interpreted:is_proc({
      cmd = "node /opt/bin/pi --model test",
      argv = { "node", "/opt/bin/pi", "--model", "test" },
      executable = "node",
      runtime_executable = "/usr/bin/node",
    }))
    assert.is_true(command_sensitive:is_proc({ cmd = "/opt/bin/custom --agent-mode", runtime_executable = "custom" }))
    assert.is_false(command_sensitive:is_proc({ cmd = "/usr/bin/cat custom --agent-mode", runtime_executable = "cat" }))
  end)
end)

describe("cli tool formatting", function()
  it("Antigravity and Qwen formatters return escaped text", function()
    for _, name in ipairs({ "antigravity", "qwen" }) do
      local file = vim.api.nvim_get_runtime_file("aj/cli/" .. name .. ".lua", false)[1]
      local config = dofile(file)
      local text = { { { "foo bar", "AjansLocFile" } } }

      assert.are.equal("foo\\ bar", config.format(text))
    end
  end)

  it("does not abort matching for invalid process regex patterns", function()
    local Tool = require("ajans.cli.tool")
    local tool = setmetatable({ config = { is_proc = "(" } }, Tool)

    assert.is_false(tool:is_proc({ cmd = "anything" }))
  end)
end)
