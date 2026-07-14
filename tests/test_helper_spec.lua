local Test = require("tests.helpers.test")
local assert = Test.assert
local describe = Test.describe
local it = Test.it

describe("test helper", function()
  it("forwards BDD calls to the current collection globals", function()
    local original = rawget(_G, "describe")
    local forwarded
    rawset(_G, "describe", function(name)
      forwarded = name
    end)

    Test.describe("current collection", function() end)
    rawset(_G, "describe", original)

    assert.are.equal("current collection", forwarded)
  end)

  it("fails clearly outside the MiniTest harness", function()
    local module_name = "tests.helpers.test"
    package.loaded[module_name] = nil
    local ok, err = pcall(require, module_name)
    package.loaded[module_name] = Test

    assert.is_false(ok)
    assert.matches("MiniTest did not install test global `describe`", tostring(err), nil, true)
  end)
end)
