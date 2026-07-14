---@module 'luassert'

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

    for name in pairs(Config.cli.tools) do
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
