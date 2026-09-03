local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Client = require("ajans.cli.session.herdr.client")
local Config = require("ajans.config")
local Herdr = require("ajans.cli.session.herdr")
local Session = require("ajans.cli.session")

local function setup_config(opts)
  pcall(vim.api.nvim_del_user_command, "Ajans")
  Config.setup(opts)
end

local function reporter()
  local reports = { ok = {}, warn = {}, error = {} }
  vim.health = {
    start = function() end,
    ok = function(message)
      reports.ok[#reports.ok + 1] = message
    end,
    warn = function(message)
      reports.warn[#reports.warn + 1] = message
    end,
    error = function(message)
      reports.error[#reports.error + 1] = message
    end,
  }
  return reports
end

describe("health", function()
  local original_executable
  local original_has
  local original_health
  local original_selected_backend
  local original_validate
  local original_server_status
  local original_trusted_socket

  before_each(function()
    original_executable = vim.fn.executable
    original_has = vim.fn.has
    original_health = vim.health
    original_selected_backend = Session.selected_backend
    original_validate = Herdr.validate
    original_server_status = Herdr.server_status
    original_trusted_socket = Client.trusted_socket
    Client.trusted_socket = function()
      return "/tmp/herdr-test.sock"
    end
    vim.fn.has = function(feature)
      return feature == "nvim-0.11.2" and 1 or 0
    end
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.has = original_has
    vim.health = original_health
    Session.selected_backend = original_selected_backend
    Herdr.validate = original_validate
    Herdr.server_status = original_server_status
    Client.trusted_socket = original_trusted_socket
    package.loaded["ajans.health"] = nil
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("checks only a selected tmux backend", function()
    setup_config({ cli = { mux = { backend = "tmux" } } })
    Session.selected_backend = function()
      return "tmux"
    end
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.ok, "Selected terminal multiplexer `tmux` is installed"))
    assert.are.same({}, reports.error)
  end)

  it("reports a missing selected tmux backend", function()
    setup_config({ cli = { mux = { backend = "tmux" } } })
    Session.selected_backend = function()
      return "tmux"
    end
    vim.fn.executable = function()
      return 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.error, "Selected terminal multiplexer `tmux` is not installed"))
  end)

  it("reports a valid selected Herdr backend and version", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.7.3"
    end
    Herdr.server_status = function()
      return { running = false }
    end
    vim.fn.executable = function()
      return 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.ok, "Selected terminal multiplexer `herdr` 0.7.3 is available"))
    assert.are.same({}, reports.error)
  end)

  it("reports an incompatible running Herdr server", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.7.3"
    end
    Herdr.server_status = function()
      return { running = true, compatible = false }
    end
    vim.fn.executable = function()
      return 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(
      vim.tbl_contains(
        reports.error,
        "The running Herdr server is incompatible with the installed client; restart the Herdr server. "
          .. "Restarting stops active pane processes; save work first or use Herdr's supported live handoff: "
          .. "https://herdr.dev/docs/session-state/"
      )
    )
  end)

  it("reports an unreadable Herdr status instead of calling the server stopped", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.7.3"
    end
    Herdr.server_status = function()
      return nil, "malformed status JSON"
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.error, "Unable to query the selected Herdr server: malformed status JSON"))
    assert.is_false(
      vim.tbl_contains(reports.ok, "The selected Herdr server is stopped and will start when Ajans creates a session")
    )
  end)

  it("reports a running Herdr server that needs restart", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.7.3"
    end
    Herdr.server_status = function()
      return { running = true, compatible = true, restart_needed = true }
    end
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "integration", "status" }, cmd)
      return { code = 0, stdout = "pi: current (v8)\nants: current (v2)\n", stderr = "" }
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(
      vim.tbl_contains(
        reports.warn,
        "The running Herdr server uses a different compatible version; restart when convenient. "
          .. "Restarting stops active pane processes; save work first or use Herdr's supported live handoff: "
          .. "https://herdr.dev/docs/session-state/"
      )
    )
    assert.is_true(vim.tbl_contains(reports.ok, "The selected Herdr server is running with a trusted local API socket"))
    assert.are.same({}, reports.error)
  end)

  it("reports current Herdr integrations for installed mapped tools", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.8.0"
    end
    Herdr.server_status = function()
      return { running = true, compatible = true }
    end
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "integration", "status" }, cmd)
      return { code = 0, stdout = "pi: current (v8)\nantigravity-cli: current (v2)\n", stderr = "" }
    end
    vim.fn.executable = function()
      return 1
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.ok, "`pi` Herdr integration is current"))
    assert.is_true(vim.tbl_contains(reports.ok, "`antigravity` Herdr integration is current"))
    assert.are.same({}, reports.error)
  end)

  it("warns about missing or stale Herdr integrations without installing", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.8.0"
    end
    Herdr.server_status = function()
      return { running = true, compatible = true }
    end
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "integration", "status" }, cmd)
      return { code = 0, stdout = "pi: not installed (x)\nantigravity-cli: stale (v1)\n", stderr = "" }
    end
    vim.fn.executable = function()
      return 1
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.are.equal(2, #reports.warn)
    assert.matches("herdr integration install antigravity%-cli", reports.warn[1])
    assert.matches("herdr integration install pi", reports.warn[2])
    assert.are.same({}, reports.error)
  end)

  it("keeps integration query failures advisory", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.8.0"
    end
    Herdr.server_status = function()
      return { running = true, compatible = true }
    end
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "integration", "status" }, cmd)
      return { code = 1, stdout = "", stderr = "status unavailable" }
    end
    vim.fn.executable = function()
      return 1
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.are.equal(2, #reports.warn)
    assert.matches("Unable to query the `antigravity` Herdr integration: status unavailable", reports.warn[1])
    assert.are.same({}, reports.error)
  end)
  it("reports an unusable running Herdr API socket", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return true, nil, "0.7.3"
    end
    Herdr.server_status = function()
      return { running = true, compatible = true, socket = "/tmp/herdr.sock" }
    end
    Client.trusted_socket = function(status)
      assert.are.equal("/tmp/herdr.sock", status.socket)
      return nil, "Herdr API socket permits group or other access"
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(
      vim.tbl_contains(
        reports.error,
        "The selected Herdr server API socket is unusable: Herdr API socket permits group or other access"
      )
    )
  end)

  it("reports Linux process fallback without claiming nonexistent port detection", function()
    setup_config({ cli = { mux = { backend = "tmux" } } })
    Session.selected_backend = function()
      return "tmux"
    end
    vim.fn.has = function(feature)
      return (feature == "nvim-0.11.2" or feature == "linux") and 1 or 0
    end
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.ok, "`ps` is not installed; using `/proc` for process discovery"))
    assert.is_false(
      vim.tbl_contains(reports.warn, "`lsof` is not installed, running processes and ports will not be detected")
    )
  end)

  it("reports the actual macOS capability degraded by missing process tools", function()
    setup_config({ cli = { mux = { backend = "tmux" } } })
    Session.selected_backend = function()
      return "tmux"
    end
    vim.fn.executable = function(name)
      return name == "tmux" and 1 or 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.warn, "`ps` is not installed; tmux process discovery is unavailable"))
    assert.is_true(
      vim.tbl_contains(reports.warn, "`lsof` is not installed; tmux working-directory detection is unavailable")
    )
  end)

  it("reports the selected Herdr validation error", function()
    setup_config({ cli = { mux = { backend = "herdr" } } })
    Session.selected_backend = function()
      return "herdr"
    end
    Herdr.validate = function()
      return false, "Herdr backend requires `herdr` >= 0.7.0 (found 0.6.9)"
    end
    vim.fn.executable = function()
      return 0
    end
    local reports = reporter()

    require("ajans.health").check()

    assert.is_true(vim.tbl_contains(reports.error, "Herdr backend requires `herdr` >= 0.7.0 (found 0.6.9)"))
  end)
end)
