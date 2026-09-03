local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Integrations = require("ajans.cli.session.herdr.integrations")
local Util = require("ajans.util")

local function completed(stdout, code, stderr)
  return { code = code or 0, stdout = stdout or "", stderr = stderr or "" }
end

describe("herdr integrations advisor", function()
  local original_warn

  before_each(function()
    original_warn = Util.warn
    Integrations.reset()
  end)

  after_each(function()
    Util.warn = original_warn
    Integrations.reset()
  end)

  for _, case in ipairs({
    { line = "pi: current (v8) (/hooks)", state = "current" },
    { line = "antigravity-cli: current (v2) (/hooks)", state = "current" },
    { line = "copilot: not installed (/hooks)", state = "missing" },
    { line = "qwen: stale (v1) (v2 available)", state = "stale" },
    { line = "qwen: outdated (v1)", state = "stale" },
    { line = "grok: something novel", state = "unknown" },
  }) do
    it(("classifies %q"):format(case.line), function()
      local statuses = Integrations.parse(case.line)
      local target = case.line:match("^(%S+):")
      assert.are.equal(case.state, statuses[target].state)
    end)
  end

  it("maps configured tools to their Herdr integration targets", function()
    assert.are.equal("antigravity-cli", Integrations.integration_for("antigravity"))
    assert.are.equal("pi", Integrations.integration_for("pi"))
    assert.is_nil(Integrations.integration_for("cline"))
    assert.is_nil(Integrations.integration_for("kimi"))
    assert.is_nil(Integrations.integration_for("amp"))
    assert.is_nil(Integrations.integration_for("maki"))
  end)

  for _, case in ipairs({
    {
      name = "current",
      stdout = "antigravity-cli: current (v2) (/hooks)\n",
      state = "current",
    },
    {
      name = "missing",
      stdout = "antigravity-cli: not installed (/hooks)\n",
      state = "missing",
    },
    {
      name = "stale",
      stdout = "antigravity-cli: stale (v1)\n",
      state = "stale",
    },
    {
      name = "missing from output",
      stdout = "pi: current (v8)\n",
      state = "unknown",
    },
  }) do
    it(("assesses the antigravity integration as %s"):format(case.name), function()
      local run = function(cmd)
        assert.are.same({ "herdr", "integration", "status" }, cmd)
        return completed(case.stdout)
      end
      local assessment = Integrations.assess("antigravity", run)
      assert.are.equal(case.state, assessment.state)
      assert.are.equal("antigravity-cli", assessment.target)
    end)
  end

  it("classifies command failures as unknown", function()
    local run = function()
      return completed("", 1, "integration status unavailable")
    end
    local assessment = Integrations.assess("pi", run)
    assert.are.equal("unknown", assessment.state)
    assert.are.equal("integration status unavailable", assessment.query_error)
  end)

  it("classifies runner errors as unknown", function()
    local run = function()
      error("boom")
    end
    local assessment = Integrations.assess("pi", run)
    assert.are.equal("unknown", assessment.state)
    assert.matches("boom", assessment.query_error)
  end)

  it("returns no assessment for tools without installable integrations", function()
    assert.is_nil(Integrations.assess("hermes", function()
      return completed()
    end))
  end)

  it("suggests only the install command for missing or stale integrations", function()
    local missing = Integrations.message({ state = "missing", target = "antigravity-cli" })
    assert.matches("herdr integration install antigravity%-cli", missing)
    assert.is_nil(missing:find("integration status", 1, true))
    local stale = Integrations.message({ state = "stale", target = "pi" })
    assert.matches("herdr integration install pi", stale)
  end)

  it("suggests only the status command for unknown states", function()
    local message = Integrations.message({ state = "unknown", target = "pi" })
    assert.matches("herdr integration status", message)
    assert.is_nil(message:find("integration install", 1, true))
  end)

  it("explains that integrations never authorize trust or input", function()
    local message = Integrations.message({ state = "missing", target = "pi" })
    assert.matches("never sign in", message)
  end)

  it("warns once per state and again when the state changes", function()
    local warnings = {}
    Util.warn = function(message)
      warnings[#warnings + 1] = message
    end
    local stdout = "pi: not installed (/hooks)\n"
    local run = function()
      return completed(stdout)
    end

    assert.is_true(Integrations.advise("pi", run))
    assert.is_false(Integrations.advise("pi", run))
    stdout = "pi: stale (v1)\n"
    assert.is_true(Integrations.advise("pi", run))
    assert.is_false(Integrations.advise("pi", run))
    stdout = "pi: current (v8)\n"
    assert.is_false(Integrations.advise("pi", run))
    assert.are.equal(2, #warnings)
  end)

  it("stays silent for current integrations and query failures", function()
    local warnings = {}
    Util.warn = function(message)
      warnings[#warnings + 1] = message
    end
    assert.is_false(Integrations.advise("pi", function()
      return completed("pi: current (v8)\n")
    end))
    assert.is_false(Integrations.advise("pi", function()
      return completed("", 1, "unavailable")
    end))
    assert.are.same({}, warnings)
  end)

  it("never advises unmapped tools", function()
    local warnings = {}
    Util.warn = function(message)
      warnings[#warnings + 1] = message
    end
    assert.is_false(Integrations.advise("cline", function()
      return completed("cline: not installed\n")
    end))
    assert.are.same({}, warnings)
  end)
end)
