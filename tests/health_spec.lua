---@module 'luassert'

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

  before_each(function()
    original_executable = vim.fn.executable
    original_has = vim.fn.has
    original_health = vim.health
    original_selected_backend = Session.selected_backend
    original_validate = Herdr.validate
    original_server_status = Herdr.server_status
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
        "The running Herdr server is incompatible with the installed client; restart the Herdr server"
      )
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
