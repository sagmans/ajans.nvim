local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Commands = require("ajans.commands")
local Util = require("ajans.util")

---@class tests.commands.Line
---@field args string
---@field range? integer

---@class tests.commands.Runner
---@field cmd fun(line:tests.commands.Line)
local CommandRunner = Commands --[[@as tests.commands.Runner]]

local function capture_errors()
  local errors = {}
  local original = Util.error
  Util.error = function(msg)
    table.insert(errors, msg)
  end
  return errors, function()
    Util.error = original
  end
end

describe("commands", function()
  it("routes cli retry to the retry API", function()
    local called
    local original = package.loaded["ajans.cli"]
    package.loaded["ajans.cli"] = {
      retry = function(opts)
        called = opts
      end,
    }
    local cmd = Commands.commands.cli.retry
    cmd({ name = "pi" })
    package.loaded["ajans.cli"] = original
    assert.are.same({ name = "pi" }, called)
  end)
  describe("argparse", function()
    local cases = {
      {
        name = "returns empty table for empty string",
        input = "",
        expected = {},
      },
      {
        name = "parses bare identifiers",
        input = "name=copilot focus=true",
        expected = { name = "copilot", focus = true },
      },
      {
        name = "handles table values",
        input = 'name=copilot tags={"a","b","c"}',
        expected = { name = "copilot", tags = { "a", "b", "c" } },
      },
      {
        name = "handles table values with keys",
        input = "name=copilot foo = { a = 1, b = 2 }",
        expected = { name = "copilot", foo = { a = 1, b = 2 } },
      },
      {
        name = "does not expose the Neovim API table",
        input = "api=vim",
        expected = { api = "vim" },
      },
      {
        name = "allows dotted string values",
        input = 'msg="review foo.lua" url="https://example.com/docs"',
        expected = { msg = "review foo.lua", url = "https://example.com/docs" },
      },
      {
        name = "allows decimal values",
        input = "temperature=1.2",
        expected = { temperature = 1.2 },
      },
      {
        name = "rejects field access in sandboxed args",
        input = "api=vim.fn",
        expected = nil,
        error_patterns = { "field access is not allowed" },
      },
      {
        name = "rejects string metatable field access",
        input = 'api=("x").dump',
        expected = nil,
        error_patterns = { "field access is not allowed" },
      },
      {
        name = "reports invalid lua",
        input = "focus=",
        expected = nil,
        error_patterns = { "Invalid args" },
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local errors, restore = capture_errors()
        local result = Commands.argparse(case.input)
        restore()

        assert.are.same(case.expected, result)
        if case.error_patterns then
          assert.are.equal(#case.error_patterns, #errors)
          for i, pattern in ipairs(case.error_patterns) do
            assert.matches(pattern, errors[i])
          end
        else
          assert.are.same({}, errors)
        end
      end)
    end
  end)

  describe("parse", function()
    local function sorted(list)
      local copy = {}
      for _, value in ipairs(list or {}) do
        table.insert(copy, value)
      end
      table.sort(copy)
      return copy
    end

    local cases = {
      {
        name = "resolves nested command",
        input = "cli show name=copilot",
        expect_command = function()
          local cli = Commands.commands.cli
          assert(type(cli) == "table")
          return rawget(cli, "show")
        end,
        expected_args = { name = "copilot" },
      },
      {
        name = "completes root commands",
        input = "",
        expected_completions = { "cli" },
      },
      {
        name = "completes subcommands",
        input = "cli ",
        expected_completions = vim.tbl_keys(Commands.commands.cli),
      },
      {
        name = "filters by prefix",
        input = "cli s",
        expected_completions = { "select", "show", "send" },
      },
      {
        name = "returns empty for unknown command",
        input = "bogus",
        expected_completions = {},
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local errors, restore = capture_errors()
        local cmd, args = Commands.parse(case.input)
        restore()

        assert.are.same({}, errors)
        if case.expect_command then
          assert.are.equal(case.expect_command(), cmd)
          assert.are.same(case.expected_args, args)
        else
          assert.are.same(sorted(case.expected_completions), sorted(cmd or {}))
        end
      end)
    end
  end)

  describe("complete", function()
    local function sorted(list)
      local copy = {}
      for _, value in ipairs(list or {}) do
        table.insert(copy, value)
      end
      table.sort(copy)
      return copy
    end

    local cases = {
      {
        name = "strips command prefix",
        input = "Ajans ",
        expected = { "cli" },
      },
      {
        name = "suggests subcommands",
        input = "Ajans cli s",
        expected = { "select", "show", "send" },
      },
      {
        name = "returns empty when no matches",
        input = "Ajans unknown",
        expected = {},
      },
    }

    for _, case in ipairs(cases) do
      it(case.name, function()
        local result = Commands.complete(case.input)
        assert.are.same(sorted(case.expected), sorted(result))
      end)
    end
  end)

  describe("cmd", function()
    local original_commands
    local calls

    local cases = {
      {
        name = "executes resolved command",
        input = "cli show focus=true",
        expected_calls = {
          { name = "cli.show", args = { focus = true } },
        },
        expected_errors = {},
      },
      {
        name = "reports invalid args",
        input = "cli show focus=",
        expected_calls = {},
        error_patterns = { "Invalid args" },
      },
      {
        name = "reports unknown command",
        input = "bogus",
        expected_calls = {},
        error_patterns = { "Invalid command" },
      },
    }

    before_each(function()
      original_commands = Commands.commands
      calls = {}
      Commands.commands = {
        cli = {
          show = function(args)
            table.insert(calls, { name = "cli.show", args = vim.deepcopy(args) })
          end,
        },
      }
    end)

    after_each(function()
      Commands.commands = original_commands
      calls = nil
    end)

    for _, case in ipairs(cases) do
      it(case.name, function()
        local errors, restore = capture_errors()
        CommandRunner.cmd({ args = case.input })
        restore()

        assert.are.same(case.expected_calls, calls or {})
        if case.error_patterns then
          assert.are.equal(#case.error_patterns, #errors)
          for i, pattern in ipairs(case.error_patterns) do
            assert.matches(pattern, errors[i])
          end
        else
          assert.are.same({}, errors)
        end
      end)
    end
  end)
end)
