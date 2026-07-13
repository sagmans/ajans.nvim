---@module 'luassert'

local Session = require("ajans.cli.session")
local Status = require("ajans.status")

local function sorted_cli_status()
  local sessions = Status.cli()
  table.sort(sessions, function(left, right)
    return tostring(left.id) < tostring(right.id)
  end)
  return sessions
end

local function set_cli_last_update(value)
  for index = 1, math.huge do
    local name = debug.getupvalue(Status.cli, index)
    if not name then
      break
    end
    if name == "cli_last_update" then
      debug.setupvalue(Status.cli, index, value)
      return
    end
  end
  error("cli_last_update upvalue not found")
end

describe("status", function()
  local original_attached

  before_each(function()
    original_attached = Session.attached
  end)

  after_each(function()
    Session.attached = original_attached
  end)

  it("returns no CLI sessions when none are attached", function()
    Session.attached = function()
      return {}
    end

    Status.setup()

    assert.are.same({}, Status.cli())
  end)

  it("returns attached CLI sessions with normalized fields", function()
    Session.attached = function()
      return {
        claude = {
          id = "claude",
          tool = { name = "claude" },
          cwd = "/tmp/project",
          backend = "terminal",
          mux_backend = "herdr",
          mux_identity = "herdr:term-1",
          started = true,
        },
        opencode = {
          id = "opencode",
          tool = { name = "opencode" },
          cwd = "/tmp/other",
          backend = "herdr",
          external = true,
          identity = "herdr:term-2",
          parent = { id = "parent" },
        },
      }
    end

    Status.setup()

    assert.are.same({
      {
        id = "claude",
        tool = "claude",
        cwd = "/tmp/project",
        backend = "herdr",
        external = false,
        terminal = true,
        identity = "herdr:term-1",
      },
      {
        id = "opencode",
        tool = "opencode",
        cwd = "/tmp/other",
        backend = "herdr",
        external = true,
        terminal = false,
        identity = "herdr:term-2",
      },
    }, sorted_cli_status())
  end)

  it("keeps partial CLI session data without failing", function()
    Session.attached = function()
      return {
        missing = {
          cwd = "/tmp/missing",
        },
        string_tool = {
          id = "string_tool",
          tool = "claude",
        },
      }
    end

    Status.setup()

    assert.are.same({
      {
        id = "missing",
        cwd = "/tmp/missing",
      },
      {
        id = "string_tool",
        tool = "claude",
      },
    }, sorted_cli_status())
  end)

  it("refreshes CLI cache when attach and detach events fire", function()
    local attached = {}
    Session.attached = function()
      return attached
    end

    Status.setup()
    assert.are.same({}, Status.cli())

    attached = {
      claude = {
        id = "claude",
        tool = { name = "claude" },
        cwd = "/tmp/project",
      },
    }
    vim.api.nvim_exec_autocmds("User", { pattern = "AjansCliAttach" })

    assert.are.same({
      {
        id = "claude",
        tool = "claude",
        cwd = "/tmp/project",
      },
    }, Status.cli())

    attached = {}
    vim.api.nvim_exec_autocmds("User", { pattern = "AjansCliDetach" })

    assert.are.same({}, Status.cli())
  end)

  it("refreshes CLI cache after the periodic refresh interval", function()
    local calls = 0
    Session.attached = function()
      calls = calls + 1
      if calls == 1 then
        return {}
      end
      return {
        claude = {
          id = "claude",
          tool = { name = "claude" },
          cwd = "/tmp/project",
        },
      }
    end

    Status.setup()
    set_cli_last_update(vim.uv.now() - 5001)

    assert.are.same({
      {
        id = "claude",
        tool = "claude",
        cwd = "/tmp/project",
      },
    }, Status.cli())
  end)
end)
