local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Util = require("ajans.util")

describe("split_words", function()
  -- should split a string in alpha / non-alpha parts
  local cases = {
    { "abcd", { "abcd" } },
    { "abcd ", { "abcd", " " } },
    { " ", { " " } },
    { "abcd.", { "abcd", "." } },
    { "abcd.?", { "abcd", ".", "?" } },
    { "abc123", { "abc123" } },
    { "123abc", { "123abc" } },
    { "abc 123", { "abc", " ", "123" } },
    { "abc\t123", { "abc", "\t", "123" } },
    { "abc\n123", { "abc", "\n", "123" } },
    { "abc.def", { "abc", ".", "def" } },
    { "abc.def.ghi", { "abc", ".", "def", ".", "ghi" } },
    { "abc_def", { "abc_def" } },
    { "abc-def", { "abc", "-", "def" } },
    { "abc+def", { "abc", "+", "def" } },
    { "abc*def", { "abc", "*", "def" } },
    { "abc/def", { "abc", "/", "def" } },
    { "abc=def", { "abc", "=", "def" } },
    { "café", { "café" } },
    { "😀", { "😀" } },
    { "foo😀bar", { "foo", "😀", "bar" } },
    { "ありがとう", { "あ", "り", "が", "と", "う" } },
    {
      'local cli = require("ajans.cli").show()',
      {
        "local",
        " ",
        "cli",
        " ",
        "=",
        " ",
        "require",
        "(",
        '"',
        "ajans",
        ".",
        "cli",
        '"',
        ")",
        ".",
        "show",
        "(",
        ")",
      },
    },
  }

  for _, case in ipairs(cases) do
    it(case[1] .. " => " .. vim.inspect(case[2]), function()
      -- vim.o.iskeyword = "@,48-57,_,192-255"
      assert.are.same(case[2], Util.split_words(case[1]))
    end)
  end
end)

describe("split_chars", function()
  -- ensure split_chars breaks strings into individual characters
  local cases = {
    { "abc", { "a", "b", "c" } },
    { "abc def", { "a", "b", "c", " ", "d", "e", "f" } },
    { "abc\tdef", { "a", "b", "c", "\t", "d", "e", "f" } },
    { "abc\ndef", { "a", "b", "c", "\n", "d", "e", "f" } },
    { "0.1", { "0", ".", "1" } },
    { "😀", { "😀" } },
    { "😀😃", { "😀", "😃" } },
    { "👍🏼", { "👍", "🏼" } },
    { "café", { "c", "a", "f", "é" } },
    { "ありがとう", { "あ", "り", "が", "と", "う" } },
  }

  for _, case in ipairs(cases) do
    it(case[1] .. " => " .. vim.inspect(case[2]), function()
      assert.are.same(case[2], Util.split_chars(case[1]))
    end)
  end
end)

describe("debounce", function()
  local original_new_timer
  local original_schedule_wrap

  before_each(function()
    original_new_timer = vim.uv.new_timer
    original_schedule_wrap = vim.schedule_wrap
  end)

  after_each(function()
    vim.uv.new_timer = original_new_timer
    vim.schedule_wrap = original_schedule_wrap
  end)

  it("closes superseded and fired timers", function()
    local timers = {}
    vim.schedule_wrap = function(cb)
      return cb
    end
    vim.uv.new_timer = function()
      local timer = { closed = false }
      function timer:start(_, _, cb)
        self.cb = cb
      end
      function timer:stop()
        self.stopped = true
      end
      function timer:close()
        self.closed = true
      end
      function timer:is_closing()
        return self.closed
      end
      timers[#timers + 1] = timer
      return timer
    end

    local calls = 0
    local debounced = Util.debounce(function()
      calls = calls + 1
    end, 10)
    debounced()
    debounced()
    timers[2].cb()

    assert.is_true(timers[1].closed)
    assert.is_true(timers[2].closed)
    assert.are.equal(1, calls)
  end)
end)
