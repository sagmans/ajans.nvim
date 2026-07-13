---@module 'luassert'

local Config = require("ajans.config")
local Herdr = require("ajans.cli.session.herdr")
local Util = require("ajans.util")

local function fresh_herdr()
  return assert(loadfile(vim.uv.cwd() .. "/lua/ajans/cli/session/herdr.lua"))()
end

local function completed(stdout, code, stderr)
  return { code = code or 0, stdout = stdout or "", stderr = stderr or "" }
end

local function success(result)
  return completed(vim.json.encode({ id = "test", result = result }) .. "\n")
end

local function failure(code, message)
  return completed("", 1, vim.json.encode({ id = "test", error = { code = code, message = message } }) .. "\n")
end

local function setup_config(opts)
  pcall(vim.api.nvim_del_user_command, "Ajans")
  Config.setup(opts)
end

local function test_tool(opts)
  opts = opts or {}
  return {
    name = opts.name or "claude",
    cmd = opts.cmd or { "claude", "--flag" },
    env = opts.env,
    mux_focus = opts.mux_focus,
  }
end

local function new_session(opts)
  opts = opts or {}
  local tool = opts.tool or test_tool()
  local session = setmetatable({
    tool = tool,
    cwd = opts.cwd or "/tmp/project",
    sid = opts.sid or (tool.name .. " abc123"),
    id = opts.id or (tool.name .. " abc123"),
    started = opts.started,
    herdr_terminal_id = opts.herdr_terminal_id,
    herdr_pane_id = opts.herdr_pane_id,
    herdr_workspace_id = opts.herdr_workspace_id,
    herdr_tab_id = opts.herdr_tab_id,
    herdr_agent = opts.herdr_agent,
    herdr_placement = opts.herdr_placement,
  }, Herdr)
  session:init()
  return session
end

local function find_call(calls, prefix)
  for _, call in ipairs(calls) do
    local found = true
    for index, value in ipairs(prefix) do
      if call.cmd[index] ~= value then
        found = false
        break
      end
    end
    if found then
      return call
    end
  end
end

local function assert_pair(cmd, key, value)
  for index = 1, #cmd - 1 do
    if cmd[index] == key and cmd[index + 1] == value then
      return
    end
  end
  error(("expected %s %s in %s"):format(key, value, table.concat(cmd, " ")))
end

describe("herdr backend", function()
  local original_executable
  local original_has
  local original_system
  local original_hrtime
  local original_run
  local original_run_many
  local original_spawn
  local original_wait
  local original_validate
  local original_version
  local original_server_status
  local original_server_running
  local original_is_usable
  local original_supports_snapshot
  local original_ensure_server
  local original_error
  local original_info
  local original_herdr_env
  local original_workspace_id
  local original_tab_id
  local original_pane_id

  before_each(function()
    original_executable = vim.fn.executable
    original_has = vim.fn.has
    original_system = vim.system
    original_hrtime = vim.uv.hrtime
    original_run = Herdr._run
    original_run_many = Herdr._run_many
    Herdr._run_many = function(commands)
      return vim.tbl_map(function(cmd)
        return Herdr._run(cmd, { text = true })
      end, commands)
    end
    original_spawn = Herdr._spawn
    original_wait = Herdr._wait
    original_validate = Herdr.validate
    original_version = Herdr.version
    original_server_status = Herdr.server_status
    original_server_running = Herdr.is_server_running
    original_is_usable = Herdr.is_usable
    original_supports_snapshot = Herdr.supports_snapshot
    Herdr.supports_snapshot = function()
      return true
    end
    original_ensure_server = Herdr.ensure_server
    original_error = Util.error
    original_info = Util.info
    original_herdr_env = vim.env.HERDR_ENV
    original_workspace_id = vim.env.HERDR_WORKSPACE_ID
    original_tab_id = vim.env.HERDR_TAB_ID
    original_pane_id = vim.env.HERDR_PANE_ID
    vim.fn.has = function()
      return 0
    end
    vim.env.HERDR_ENV = nil
    vim.env.HERDR_WORKSPACE_ID = nil
    vim.env.HERDR_TAB_ID = nil
    vim.env.HERDR_PANE_ID = nil
    setup_config({ cli = { mux = { backend = "herdr" } } })
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.has = original_has
    vim.system = original_system
    vim.uv.hrtime = original_hrtime
    Herdr._run = original_run
    Herdr._run_many = original_run_many
    Herdr._spawn = original_spawn
    Herdr._wait = original_wait
    Herdr.validate = original_validate
    Herdr.version = original_version
    Herdr.server_status = original_server_status
    Herdr.is_server_running = original_server_running
    Herdr.is_usable = original_is_usable
    Herdr.supports_snapshot = original_supports_snapshot
    Herdr.ensure_server = original_ensure_server
    Util.error = original_error
    Util.info = original_info
    vim.env.HERDR_ENV = original_herdr_env
    vim.env.HERDR_WORKSPACE_ID = original_workspace_id
    vim.env.HERDR_TAB_ID = original_tab_id
    vim.env.HERDR_PANE_ID = original_pane_id
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("parses and compares semantic versions", function()
    assert.are.same({ 0, 7, 0 }, Herdr.parse_version("herdr 0.7.0"))
    assert.is_true(Herdr.version_at_least({ 0, 7, 0 }))
    assert.is_true(Herdr.version_at_least({ 0, 8, 0 }))
    assert.is_false(Herdr.version_at_least({ 0, 6, 10 }))
  end)

  it("uses api snapshot only when the installed Herdr supports it", function()
    Herdr.supports_snapshot = original_supports_snapshot
    local versions = {
      ["0.7.0"] = false,
      ["0.7.1"] = false,
      ["0.7.2"] = true,
      ["0.7.3"] = true,
    }
    for version, supported in pairs(versions) do
      Herdr.version = function()
        return version
      end
      assert.are.equal(supported, Herdr.supports_snapshot(), version)
    end
  end)

  it("requires Herdr 0.7.0 or newer", function()
    vim.fn.executable = function(name)
      return name == "herdr" and 1 or 0
    end
    Herdr._run = function()
      return completed("herdr 0.6.10\n")
    end

    local ok, err = Herdr.validate()

    assert.is_false(ok)
    assert.matches("requires `herdr` >= 0.7.0", err)
    assert.matches("found 0.6.10", err)
  end)

  it("returns the validated Herdr version", function()
    vim.fn.executable = function()
      return 1
    end
    Herdr._run = function()
      return completed("herdr 0.7.3\n")
    end

    local ok, err, version = Herdr.validate()

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal("0.7.3", version)
  end)

  it("reports a missing Herdr executable", function()
    vim.fn.executable = function()
      return 0
    end

    local ok, err = Herdr.validate()

    assert.is_false(ok)
    assert.matches("not installed", err)
  end)

  it("rejects the out-of-scope Windows platform", function()
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or 0
    end

    local ok, err = Herdr.validate()

    assert.is_false(ok)
    assert.matches("Windows is not supported", err)
  end)

  it("bounds individual Herdr command execution", function()
    local implementation = fresh_herdr()
    local waited
    vim.system = function(cmd, opts)
      assert.are.same({ "herdr", "agent", "list" }, cmd)
      assert.is_true(opts.text)
      return {
        wait = function(_, timeout)
          waited = timeout
          return completed()
        end,
      }
    end

    implementation._run({ "herdr", "agent", "list" }, { text = true })

    assert.are.equal(implementation.COMMAND_TIMEOUT, waited)
  end)

  it("bounds process-info discovery concurrency", function()
    local implementation = fresh_herdr()
    local active = 0
    local peak = 0
    vim.system = function(cmd)
      active = active + 1
      peak = math.max(peak, active)
      return {
        wait = function()
          active = active - 1
          return completed(vim.json.encode({ cmd = cmd }))
        end,
      }
    end
    local commands = {}
    for index = 1, implementation.PROCESS_INFO_CONCURRENCY * 3 do
      commands[index] = { "herdr", "pane", "process-info", "--pane", "p" .. index }
    end

    local results = implementation._run_many(commands)

    assert.are.equal(#commands, #results)
    assert.are.equal(implementation.PROCESS_INFO_CONCURRENCY, peak)
  end)

  it("enforces one global process-info discovery deadline", function()
    local implementation = fresh_herdr()
    local tick = 0
    local spawned = 0
    local waited = 0
    local killed = 0
    vim.uv.hrtime = function()
      tick = tick + 1
      return tick <= 3 and 0 or 6 * 1e9
    end
    vim.system = function()
      spawned = spawned + 1
      return {
        wait = function(_, timeout)
          waited = waited + 1
          assert.are.equal(implementation.DISCOVERY_TIMEOUT, timeout)
          return completed()
        end,
        kill = function(_, signal)
          assert.are.equal(15, signal)
          killed = killed + 1
        end,
      }
    end
    local commands = {}
    for index = 1, implementation.PROCESS_INFO_CONCURRENCY + 1 do
      commands[index] = { "herdr", "pane", "process-info", "--pane", "p" .. index }
    end

    local results = implementation._run_many(commands)

    assert.are.equal(implementation.PROCESS_INFO_CONCURRENCY, spawned)
    assert.are.equal(1, waited)
    assert.are.equal(implementation.PROCESS_INFO_CONCURRENCY - 1, killed)
    assert.are.equal(#commands, #results)
    for index = 2, #results do
      assert.are.equal(124, results[index].code)
    end
  end)

  it("decodes JSON command results without overriding the selected Herdr namespace", function()
    local calls = {}
    Herdr._run = function(cmd, opts)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts) }
      return success({ type = "agent_list", agents = {} })
    end

    local result = Herdr.request({ "agent", "list" })

    assert.are.same({ type = "agent_list", agents = {} }, result)
    assert.are.same({ "herdr", "agent", "list" }, calls[1].cmd)
    assert.is_true(calls[1].opts.text)
  end)

  for _, case in ipairs({
    {
      name = "JSON error envelope",
      response = failure("agent_not_found", "agent disappeared"),
      expected = "agent_not_found: agent disappeared",
    },
    {
      name = "malformed success JSON",
      response = completed("not-json\n"),
      expected = "malformed JSON",
    },
    {
      name = "missing result payload",
      response = completed('{"id":"test"}\n'),
      expected = "missing `result`",
    },
  }) do
    it("reports " .. case.name, function()
      local errors = {}
      Util.error = function(message)
        errors[#errors + 1] = message
      end
      Herdr._run = function()
        return case.response
      end

      local result = Herdr.request({ "agent", "list" })

      assert.is_nil(result)
      assert.matches(case.expected, errors[1])
    end)
  end

  it("reports command execution failures", function()
    local errors = {}
    Util.error = function(message)
      errors[#errors + 1] = message
    end
    Herdr._run = function()
      error("ENOENT: herdr")
    end

    local result = Herdr.request({ "agent", "list" })

    assert.is_nil(result)
    assert.matches("Failed to execute Herdr command", errors[1])
    assert.matches("ENOENT", errors[1])
  end)

  it("treats a stopped server as empty discovery without starting one", function()
    local spawned = false
    local errors = {}
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "api", "snapshot" }, cmd)
      return completed("", 1, "failed to connect to Herdr server: Connection refused\n")
    end
    Herdr._spawn = function()
      spawned = true
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    local sessions = Herdr.sessions()

    assert.are.same({}, sessions)
    assert.is_false(spawned)
    assert.are.same({}, errors)
  end)

  it("discovers populated list inventory on Herdr 0.7.0 and 0.7.1", function()
    setup_config({
      cli = {
        mux = { backend = "herdr" },
        tools = {
          custom = {
            cmd = { "custom-agent" },
            is_proc = function(_, proc)
              return proc.cmd:find("custom%-agent") ~= nil
            end,
          },
        },
      },
    })
    Herdr.supports_snapshot = function()
      return false
    end
    local calls = {}
    local fields = {
      workspace = {
        type = "workspace_list",
        workspaces = { { workspace_id = "w1", label = "ajans:claude legacy" } },
      },
      tab = { type = "tab_list", tabs = { { tab_id = "t1", workspace_id = "w1" } } },
      pane = {
        type = "pane_list",
        panes = {
          { pane_id = "p1", terminal_id = "term-1", workspace_id = "w1", tab_id = "t1", cwd = "/one" },
          { pane_id = "p2", terminal_id = "term-2", workspace_id = "w1", tab_id = "t1", cwd = "/two" },
        },
      },
      agent = {
        type = "agent_list",
        agents = {
          {
            name = "ajans:claude legacy",
            agent = "claude",
            pane_id = "p1",
            terminal_id = "term-1",
            workspace_id = "w1",
            tab_id = "t1",
            cwd = "/one",
          },
        },
      },
    }
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      if cmd[3] == "process-info" then
        local pane_id = cmd[#cmd]
        return success({
          type = "pane_process_info",
          process_info = {
            pane_id = pane_id,
            shell_pid = pane_id == "p1" and 10 or 20,
            foreground_processes = pane_id == "p2" and {
              { pid = 21, name = "custom-agent", argv = { "custom-agent" }, cwd = "/custom" },
            } or {},
          },
        })
      end
      return success(fields[cmd[2]])
    end

    local sessions, complete = Herdr.sessions()
    table.sort(sessions, function(left, right)
      return left.herdr_pane_id < right.herdr_pane_id
    end)

    assert.is_true(complete)
    assert.are.equal(2, #sessions)
    assert.are.equal("claude", sessions[1].tool.name)
    assert.are.same({}, sessions[1].pids)
    assert.are.equal("custom", sessions[2].tool.name)
    assert.are.equal("/custom", sessions[2].cwd)
    assert.are.same({ 20, 21 }, sessions[2].pids)
    assert.are.same({
      { "herdr", "workspace", "list" },
      { "herdr", "tab", "list" },
      { "herdr", "pane", "list" },
      { "herdr", "agent", "list" },
      { "herdr", "pane", "process-info", "--pane", "p2" },
    }, calls)
  end)

  it("rejects malformed legacy inventory before later list calls", function()
    Herdr.supports_snapshot = function()
      return false
    end
    local calls = 0
    local errors = {}
    Herdr._run = function(cmd)
      calls = calls + 1
      assert.are.same({ "herdr", "workspace", "list" }, cmd)
      return success({ type = "workspace_list" })
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    local sessions, complete = Herdr.sessions()

    assert.are.same({}, sessions)
    assert.is_false(complete)
    assert.are.equal(1, calls)
    assert.matches("missing `workspaces`", errors[1])
  end)

  it("treats a stopped Herdr 0.7.0 server as empty discovery", function()
    Herdr.supports_snapshot = function()
      return false
    end
    local calls = 0
    local errors = {}
    Herdr._run = function(cmd)
      calls = calls + 1
      assert.are.same({ "herdr", "workspace", "list" }, cmd)
      return completed("", 1, "failed to connect to Herdr server: Connection refused\n")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.are.same({}, Herdr.sessions())
    assert.are.equal(1, calls)
    assert.are.same({}, errors)
  end)

  it("starts a detached server and waits for bounded readiness only on creation", function()
    local status_checks = 0
    local spawned
    local waited
    Herdr.validate = function()
      return true
    end
    Herdr.server_status = function()
      return { running = false, compatible = true, restart_needed = false }
    end
    Herdr.is_server_running = function()
      status_checks = status_checks + 1
      return status_checks >= 1
    end
    Herdr._spawn = function(cmd, opts)
      spawned = { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts) }
      return {}
    end
    Herdr._wait = function(timeout, predicate, interval)
      waited = { timeout = timeout, interval = interval }
      return predicate()
    end

    assert.is_true(Herdr.ensure_server())
    assert.are.same({ "herdr", "server" }, spawned.cmd)
    assert.is_true(spawned.opts.detach)
    assert.are.same({ timeout = Herdr.STARTUP_TIMEOUT, interval = Herdr.STARTUP_INTERVAL }, waited)
  end)

  it("reports a bounded server startup timeout", function()
    local errors = {}
    Herdr.validate = function()
      return true
    end
    Herdr.server_status = function()
      return { running = false, compatible = true, restart_needed = false }
    end
    Herdr.is_server_running = function()
      return false
    end
    Herdr._spawn = function()
      return {}
    end
    Herdr._wait = function()
      return false
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(Herdr.ensure_server())
    assert.matches("did not become ready", errors[1])
  end)

  it("discovers every pane using stable names, label aliases, and process metadata fallback", function()
    setup_config({
      cli = {
        mux = { backend = "herdr" },
        tools = {
          custom = {
            cmd = { "custom-agent" },
            is_proc = function(_, proc)
              return proc.cmd:find("custom%-agent") ~= nil
            end,
          },
        },
      },
    })
    local calls = {}
    local snapshot = {
      type = "session_snapshot",
      snapshot = {
        workspaces = {
          { workspace_id = "w1", label = "ajans:claude abc123" },
          { workspace_id = "w2", label = "External" },
        },
        tabs = {
          { tab_id = "t1", workspace_id = "w1", label = "Main" },
          { tab_id = "t2", workspace_id = "w2", label = "Agents" },
        },
        panes = {
          { pane_id = "p1", terminal_id = "term-1", workspace_id = "w1", tab_id = "t1", cwd = "/one" },
          {
            pane_id = "p2",
            terminal_id = "term-2",
            workspace_id = "w2",
            tab_id = "t2",
            cwd = "/two",
            agent = "github-copilot",
          },
          { pane_id = "p3", terminal_id = "term-3", workspace_id = "w2", tab_id = "t2", cwd = "/three" },
          { pane_id = "p4", terminal_id = "term-4", workspace_id = "w2", tab_id = "t2", cwd = "/four" },
          {
            pane_id = "p5",
            terminal_id = "term-5",
            workspace_id = "w2",
            tab_id = "t2",
            cwd = "/five",
            agent = "antigravity",
          },
        },
        agents = {
          {
            pane_id = "p1",
            terminal_id = "term-1",
            name = "ajans:claude abc123",
            agent = "codex",
            workspace_id = "w1",
            tab_id = "t1",
            cwd = "/one",
          },
          {
            pane_id = "p2",
            terminal_id = "term-2",
            agent = "github-copilot",
            workspace_id = "w2",
            tab_id = "t2",
            cwd = "/two",
          },
        },
      },
    }
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      if cmd[2] == "api" then
        return success(snapshot)
      elseif cmd[#cmd] == "p1" then
        return success({
          type = "pane_process_info",
          process_info = { shell_pid = 10, foreground_processes = { { pid = 11, name = "claude" } } },
        })
      elseif cmd[#cmd] == "p2" then
        return success({
          type = "pane_process_info",
          process_info = { shell_pid = 20, foreground_processes = { { pid = 21, name = "copilot" } } },
        })
      elseif cmd[#cmd] == "p3" then
        return success({
          type = "pane_process_info",
          process_info = {
            pane_id = "p3",
            shell_pid = 30,
            foreground_process_group_id = 31,
            foreground_processes = {
              { pid = 32, name = "custom-agent", argv = { "custom-agent", "run" }, cwd = "/custom" },
            },
          },
        })
      elseif cmd[#cmd] == "p4" then
        return success({
          type = "pane_process_info",
          process_info = {
            pane_id = "p4",
            shell_pid = 40,
            foreground_processes = {
              { pid = 41, name = "zsh", cmdline = "zsh", cwd = "/four" },
            },
          },
        })
      elseif cmd[#cmd] == "p5" then
        return success({
          type = "pane_process_info",
          process_info = { shell_pid = 50, foreground_processes = { { pid = 51, name = "antigravity" } } },
        })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local sessions = Herdr.sessions()

    table.sort(sessions, function(a, b)
      return a.herdr_pane_id < b.herdr_pane_id
    end)
    assert.are.equal(4, #sessions)
    assert.are.equal("claude", sessions[1].tool.name)
    assert.are.equal("herdr term-1", sessions[1].id)
    assert.are.equal("herdr:term-1", sessions[1].identity)
    assert.are.equal("workspace", sessions[1].herdr_placement)
    assert.are.same({}, sessions[1].pids)
    assert.are.equal("copilot", sessions[2].tool.name)
    assert.are.same({}, sessions[2].pids)
    assert.are.equal("custom", sessions[3].tool.name)
    assert.are.equal("/custom", sessions[3].cwd)
    assert.are.same({ 30, 31, 32 }, sessions[3].pids)
    assert.are.equal("term-3", sessions[3].herdr_terminal_id)
    assert.are.equal("p3", sessions[3].herdr_pane_id)
    assert.are.equal("w2", sessions[3].herdr_workspace_id)
    assert.are.equal("t2", sessions[3].herdr_tab_id)
    assert.are.equal("antigravity", sessions[4].tool.name)
    assert.are.same({}, sessions[4].pids)

    local process_calls = vim.tbl_filter(function(cmd)
      return cmd[2] == "pane" and cmd[3] == "process-info"
    end, calls)
    assert.are.equal(2, #process_calls)
    for index, pane_id in ipairs({ "p3", "p4" }) do
      assert.are.equal(pane_id, process_calls[index][#process_calls[index]])
    end
  end)

  it("skips malformed panes before process inspection", function()
    local calls = {}
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      if cmd[2] == "api" then
        return success({
          type = "session_snapshot",
          snapshot = {
            workspaces = { { workspace_id = "w1" } },
            tabs = { { tab_id = "t1", workspace_id = "w1" } },
            agents = {},
            panes = {
              { terminal_id = "missing-pane-id", workspace_id = "w1", tab_id = "t1" },
              { pane_id = "p1", terminal_id = "term-1", workspace_id = "w1", tab_id = "t1" },
            },
          },
        })
      elseif cmd[3] == "process-info" then
        return success({ type = "pane_process_info", process_info = { foreground_processes = {} } })
      end
      error("unexpected command")
    end
    local errors = {}
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    local _, complete = Herdr.sessions()

    assert.is_false(complete)
    local process_calls = vim.tbl_filter(function(cmd)
      return cmd[3] == "process-info"
    end, calls)
    assert.are.equal(1, #process_calls)
    assert.are.equal("p1", process_calls[1][#process_calls[1]])
    assert.matches("without stable", errors[1])
  end)

  it("marks transient process metadata failures as incomplete discovery", function()
    setup_config({
      cli = {
        mux = { backend = "herdr" },
        tools = {
          custom = {
            cmd = { "custom-agent" },
            is_proc = function(_, proc)
              return proc.cmd:find("custom%-agent") ~= nil
            end,
          },
        },
      },
    })
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "api", "snapshot" }, cmd)
      return success({
        type = "session_snapshot",
        snapshot = {
          workspaces = { { workspace_id = "w1" } },
          tabs = { { tab_id = "t1", workspace_id = "w1" } },
          agents = {},
          panes = { { pane_id = "p1", terminal_id = "term-1", workspace_id = "w1", tab_id = "t1" } },
        },
      })
    end
    Herdr._run_many = function()
      return { completed("", 124, "Herdr discovery timed out") }
    end
    Util.error = function() end

    local sessions, complete = Herdr.sessions()

    assert.are.same({}, sessions)
    assert.is_false(complete)
  end)

  it("builds Ajans-owned Herdr names from a fixed cwd digest", function()
    local first = new_session({ cwd = "/tmp/one", tool = test_tool({ name = "sixteen-char-tool" }) })
    local second = new_session({ cwd = "/tmp/two", tool = test_tool({ name = "sixteen-char-tool" }) })

    assert.matches("^ajans:sixteen%-char%-tool [0-9a-f]+$", first:agent_name())
    assert.are.equal(#"ajans:sixteen-char-tool " + 12, #first:agent_name())
    assert.are_not.equal(first:agent_name(), second:agent_name())
  end)

  for _, case in ipairs({
    { label = "github-copilot", tool = "copilot" },
    { label = "GitHub Copilot", tool = "copilot" },
    { label = "antigravity", tool = "antigravity" },
    { label = "opencode", tool = "opencode" },
  }) do
    it("maps Herdr agent label " .. case.label, function()
      assert.are.equal(case.tool, Herdr.tool_name_for_label(case.label))
    end)
  end

  it("creates an isolated workspace transaction and returns direct agent attach argv", function()
    local calls = {}
    local tool = test_tool({ env = { ZED = "last", ALPHA = "first", REMOVE_ME = false } })
    local session = new_session({ tool = tool })
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd, opts)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts or {}) }
      if cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "w1" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root", terminal_id = "term-root" },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-agent",
            pane_id = "agent-pane",
            workspace_id = "w1",
            tab_id = "t1",
            cwd = "/tmp/project",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({
          type = "pane_process_info",
          process_info = { shell_pid = 100, foreground_processes = { { pid = 101, name = "claude" } } },
        })
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.are.same({ "herdr", "agent", "attach", "term-agent" }, attach.cmd)
    assert.are.equal("herdr term-agent", session.id)
    assert.are.equal("herdr:term-agent", session.identity)
    assert.are.equal("agent-pane", session.herdr_pane_id)
    assert.are.same({ 100, 101 }, session.pids)
    assert.is_true(session.started)
    assert.is_false(session.external)

    local create = assert(find_call(calls, { "herdr", "workspace", "create" })).cmd
    assert_pair(create, "--cwd", "/tmp/project")
    assert_pair(create, "--label", session:agent_name())
    local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
    assert_pair(start, "--workspace", "w1")
    assert_pair(start, "--tab", "t1")
    assert_pair(start, "--env", "ALPHA=first")
    assert_pair(start, "--env", "ZED=last")
    assert.are.same({ "env", "-u", "REMOVE_ME", "--", "claude", "--flag" }, vim.list_slice(start, #start - 5))
    local close = assert(find_call(calls, { "herdr", "pane", "close" })).cmd
    assert.are.equal("root", close[4])
  end)

  it("rolls back a workspace when agent launch fails", function()
    local calls = {}
    local errors = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      if cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "w1" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root" },
        })
      elseif cmd[2] == "agent" then
        return failure("agent_start_failed", "spawn failed")
      elseif cmd[2] == "workspace" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end

    assert.is_nil(session:start())
    assert.is_not_nil(find_call(
      vim.tbl_map(function(cmd)
        return { cmd = cmd }
      end, calls),
      { "herdr", "workspace", "close", "w1" }
    ))
    assert.matches("agent_start_failed", errors[1])
  end)

  it("rolls back an isolated workspace when temporary pane cleanup fails", function()
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "w1" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root" },
        })
      elseif cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = { terminal_id = "term-1", pane_id = "agent-pane", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return failure("pane_close_failed", "root stayed open")
      elseif cmd[2] == "workspace" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "workspace", "close", "w1" }))
    assert.is_false(session.started == true)
  end)

  it("reports a rollback failure with the exact manual cleanup command", function()
    local errors = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      if cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "leaked-workspace" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root" },
        })
      elseif cmd[2] == "agent" then
        return failure("agent_start_failed", "spawn failed")
      elseif cmd[2] == "workspace" and cmd[3] == "close" then
        return failure("workspace_close_failed", "still open")
      end
      error("unexpected command")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    session:start()

    assert.matches("herdr workspace close leaked%-workspace", errors[#errors])
  end)

  it("creates a Herdr tab for window mode and removes its temporary root pane", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "window" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "tab" and cmd[3] == "create" then
        return success({
          type = "tab_created",
          tab = { tab_id = "new-tab", workspace_id = "host-workspace" },
          root_pane = { pane_id = "tab-root" },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-window",
            pane_id = "pane-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ type = "pane_process_info", process_info = {} })
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    Util.info = function() end

    local attach = session:start()

    assert.is_nil(attach)
    assert.is_true(session.external)
    local create = assert(find_call(calls, { "herdr", "tab", "create" })).cmd
    assert_pair(create, "--workspace", "host-workspace")
    assert_pair(create, "--label", session:agent_name())
    local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
    assert_pair(start, "--workspace", "host-workspace")
    assert_pair(start, "--tab", "new-tab")
    assert.are.equal("tab-root", assert(find_call(calls, { "herdr", "pane", "close" })).cmd[4])
  end)

  it("rolls back a new tab after a partial creation failure", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "window" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "tab" and cmd[3] == "create" then
        return success({
          type = "tab_created",
          tab = { tab_id = "new-tab", workspace_id = "host-workspace" },
          root_pane = { pane_id = "tab-root" },
        })
      elseif cmd[2] == "agent" then
        return failure("agent_start_failed", "failed")
      elseif cmd[2] == "tab" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "tab", "close", "new-tab" }))
  end)

  it("rolls back a new tab when temporary pane cleanup fails", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "window" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local messages = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "tab" and cmd[3] == "create" then
        return success({
          type = "tab_created",
          tab = { tab_id = "new-tab", workspace_id = "host-workspace" },
          root_pane = { pane_id = "tab-root" },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-window",
            pane_id = "pane-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return failure("pane_close_failed", "root stayed open")
      elseif cmd[2] == "tab" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end
    Util.info = function(message)
      messages[#messages + 1] = message
    end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "tab", "close", "new-tab" }))
    assert.is_false(session.started == true)
    assert.are.same({}, messages)
  end)

  for _, case in ipairs({
    {
      name = "vertical fractional split",
      vertical = true,
      size = 0.7,
      split = "right",
      split_direction = "right",
      dimension = { width = 120, height = 40 },
      pane = { x = 60, y = 0, width = 60, height = 40 },
      resize_direction = "left",
      amount = "0.2",
      final_ratio = 0.3,
    },
    {
      name = "vertical cell split",
      vertical = true,
      size = 20,
      split = "right",
      split_direction = "right",
      dimension = { width = 100, height = 40 },
      pane = { x = 50, y = 0, width = 50, height = 40 },
      resize_direction = "right",
      amount = "0.3",
      final_ratio = 0.8,
    },
    {
      name = "horizontal cell split",
      vertical = false,
      size = 10,
      split = "down",
      split_direction = "down",
      dimension = { width = 100, height = 40 },
      pane = { x = 0, y = 20, width = 100, height = 20 },
      resize_direction = "down",
      amount = "0.25",
      final_ratio = 0.75,
    },
  }) do
    it("sizes a " .. case.name .. " from pane layout", function()
      setup_config({
        cli = { mux = { backend = "herdr", create = "split", split = { vertical = case.vertical, size = case.size } } },
      })
      vim.env.HERDR_ENV = "1"
      vim.env.HERDR_WORKSPACE_ID = "host-workspace"
      vim.env.HERDR_TAB_ID = "host-tab"
      local calls = {}
      local session = new_session()
      Herdr.ensure_server = function()
        return true
      end
      Herdr._run = function(cmd)
        calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
        if cmd[2] == "agent" and cmd[3] == "start" then
          return success({
            type = "agent_started",
            agent = {
              terminal_id = "term-split",
              pane_id = "pane-split",
              workspace_id = "host-workspace",
              tab_id = "host-tab",
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "process-info" then
          return success({ type = "pane_process_info", process_info = {} })
        elseif cmd[2] == "pane" and cmd[3] == "layout" then
          return success({
            type = "pane_layout",
            layout = {
              area = { x = 0, y = 0, width = 200, height = 80 },
              panes = { { pane_id = "pane-split", rect = case.pane } },
              splits = {
                {
                  id = "outer",
                  direction = case.split_direction,
                  ratio = 0.4,
                  rect = { x = 0, y = 0, width = 200, height = 80 },
                },
                {
                  id = "immediate",
                  direction = case.split_direction,
                  ratio = 0.5,
                  rect = { x = 0, y = 0, width = case.dimension.width, height = case.dimension.height },
                },
              },
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "resize" then
          return success({
            type = "pane_resize",
            resize = {
              changed = true,
              layout = {
                panes = { { pane_id = "pane-split", rect = case.pane } },
                splits = {
                  {
                    id = "immediate",
                    direction = case.split_direction,
                    ratio = case.final_ratio,
                    rect = { x = 0, y = 0, width = case.dimension.width, height = case.dimension.height },
                  },
                },
              },
            },
          })
        end
        error("unexpected command: " .. table.concat(cmd, " "))
      end
      Util.info = function() end

      assert.is_nil(session:start())

      local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
      assert_pair(start, "--workspace", "host-workspace")
      assert_pair(start, "--tab", "host-tab")
      assert_pair(start, "--split", case.split)
      local resize = assert(find_call(calls, { "herdr", "pane", "resize" })).cmd
      assert_pair(resize, "--pane", "pane-split")
      assert_pair(resize, "--direction", case.resize_direction)
      assert_pair(resize, "--amount", case.amount)
    end)
  end

  it("rolls back when Herdr cannot achieve the configured split size", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split", split = { size = 0.8 } } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[3] == "process-info" then
        return success({ type = "pane_process_info", process_info = {} })
      elseif cmd[3] == "layout" then
        return success({
          type = "pane_layout",
          layout = {
            panes = { { pane_id = "pane-split", rect = { x = 50, y = 0, width = 50, height = 40 } } },
            splits = { { direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } } },
          },
        })
      elseif cmd[3] == "resize" then
        return success({
          type = "pane_resize",
          resize = {
            changed = true,
            layout = {
              panes = { { pane_id = "pane-split", rect = { x = 10, y = 0, width = 90, height = 40 } } },
              splits = { { direction = "right", ratio = 0.1, rect = { x = 0, y = 0, width = 100, height = 40 } } },
            },
          },
        })
      elseif cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "pane", "close", "pane-split" }))
    assert.is_false(session.started == true)
  end)

  it("rejects cell split sizes outside the shared layout range", function()
    setup_config({ cli = { mux = { backend = "herdr", split = { vertical = true, size = 5 } } } })
    local errors = {}
    local calls = {}
    local session = new_session()
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      assert.are.equal("layout", cmd[3])
      return success({
        type = "pane_layout",
        layout = {
          panes = { { pane_id = "pane-split", rect = { x = 50, y = 0, width = 50, height = 40 } } },
          splits = {
            { direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
          },
        },
      })
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(session:size_split("pane-split", "right"))
    assert.are.equal(1, #calls)
    assert.matches("outside the shared", errors[1])
  end)

  it("closes a pane returned by a malformed split launch response", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = {
            pane_id = "partial-pane",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "pane", "close", "partial-pane" }))
    assert.is_false(session.started == true)
  end)

  it("closes a newly created split pane when sizing fails", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split", split = { size = 0.7 } } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ type = "pane_process_info", process_info = {} })
      elseif cmd[2] == "pane" and cmd[3] == "layout" then
        return failure("pane_layout_unavailable", "layout failed")
      elseif cmd[2] == "pane" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command")
    end
    Util.error = function() end

    session:start()

    assert.is_not_nil(find_call(calls, { "herdr", "pane", "close", "pane-split" }))
    assert.is_false(session.started == true)
  end)

  for _, case in ipairs({
    {
      name = "classified agent",
      state = { herdr_agent = true, herdr_terminal_id = "term-1", herdr_pane_id = "pane-1" },
      expected = { "herdr", "agent", "attach", "term-1" },
    },
    {
      name = "custom process pane fallback",
      state = { herdr_agent = false, herdr_terminal_id = "term-2", herdr_pane_id = "pane-2" },
      expected = { "herdr", "terminal", "attach", "term-2" },
    },
  }) do
    it("attaches a " .. case.name, function()
      local session = new_session(vim.tbl_extend("force", { started = true }, case.state))

      assert.are.same(case.expected, session:attach().cmd)
    end)
  end

  it("keeps external Herdr tabs and splits outside the Neovim terminal wrapper", function()
    for _, placement in ipairs({ "tab", "split" }) do
      local session = new_session({
        started = true,
        herdr_agent = true,
        herdr_terminal_id = "term-" .. placement,
        herdr_pane_id = "pane-" .. placement,
        herdr_placement = placement,
      })
      session.external = true
      assert.is_nil(session:attach())
    end
  end)

  it("preserves ordered literal multiline sends, focus signaling, and separate Enter", function()
    local calls = {}
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = test_tool({ mux_focus = true }),
    })
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      return cmd[2] == "agent" and success({ type = "ok" }) or completed()
    end

    session:send("first\nsecond")
    session:send("third")
    session:submit()

    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "escape", "[", "I" }, calls[1])
    assert.are.same({ "herdr", "agent", "send", "term-1", "first\nsecond" }, calls[2])
    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "escape", "[", "I" }, calls[3])
    assert.are.same({ "herdr", "agent", "send", "term-1", "third" }, calls[4])
    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "enter" }, calls[5])
  end)

  it("sends literal text to an unclassified custom pane and does not wedge after failure", function()
    local calls = {}
    local failed = true
    local session = new_session({
      started = true,
      herdr_agent = false,
      herdr_terminal_id = "term-custom",
      herdr_pane_id = "pane-custom",
    })
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      if cmd[2] == "pane" and cmd[3] == "send-text" and failed then
        failed = false
        return failure("pane_send_failed", "gone")
      end
      return completed()
    end
    Util.error = function() end

    session:send("first\nsecond")
    session:send("third")
    session:submit()

    assert.are.same({ "herdr", "pane", "send-text", "pane-custom", "first\nsecond" }, calls[1])
    assert.are.same({ "herdr", "pane", "send-text", "pane-custom", "third" }, calls[2])
    assert.are.same({ "herdr", "pane", "send-keys", "pane-custom", "enter" }, calls[3])
    assert.is_false(session._sending)
  end)

  it("refuses input without the required stable pane identity", function()
    local calls = 0
    local session = new_session({ started = true, herdr_agent = true, herdr_terminal_id = "term-1" })
    Herdr._run = function()
      calls = calls + 1
      return completed()
    end

    assert.is_false(session:send("prompt"))
    assert.is_false(session:submit())
    assert.are.equal(0, calls)
  end)

  it("validates a custom pane still runs the configured tool", function()
    local process = "custom-agent"
    local tool = test_tool({ name = "custom" })
    tool.is_proc = function(_, proc)
      return proc.cmd == "custom-agent"
    end
    local session = new_session({
      started = true,
      herdr_agent = false,
      herdr_terminal_id = "term-custom",
      herdr_pane_id = "pane-custom",
      tool = tool,
    })
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "pane", "process-info", "--pane", "pane-custom" }, cmd)
      return success({ process_info = { foreground_processes = { { pid = 42, cmdline = process } } } })
    end

    assert.is_true(session:accepts_automated_input())
    process = "zsh"
    assert.is_false(session:accepts_automated_input())
  end)

  it("does not submit Enter after a failed send", function()
    local calls = {}
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      return failure("agent_send_failed", "gone")
    end
    Util.error = function() end

    assert.is_false(session:send("partial"))
    assert.is_false(session:submit())
    assert.are.equal(1, #calls)
    assert.are.same({ "herdr", "agent", "send", "term-1", "partial" }, calls[1])
  end)

  it("chunks large UTF-8 sends and redacts failed prompt contents", function()
    local calls = {}
    local errors = {}
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    local secret = string.rep("a", Herdr.SEND_CHUNK_BYTES) .. "€secret"
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      return #calls == 1 and success({ type = "ok" }) or failure("agent_send_failed", "gone")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    session:send(secret)

    assert.are.equal(2, #calls)
    assert.are.equal(secret, calls[1][5] .. calls[2][5])
    assert.is_false(errors[1]:find("secret", 1, true) ~= nil)
    assert.matches("<redacted>", errors[1])
  end)

  for _, case in ipairs({
    { name = "agent", agent = true, command = { "herdr", "agent", "get", "term-1" } },
    { name = "custom pane", agent = false, command = { "herdr", "pane", "get", "pane-1" } },
  }) do
    it("checks " .. case.name .. " liveness by stable identity", function()
      local session = new_session({
        started = true,
        herdr_agent = case.agent,
        herdr_terminal_id = "term-1",
        herdr_pane_id = "pane-1",
      })
      Herdr._run = function(cmd)
        assert.are.same(case.command, cmd)
        return success({ type = case.agent and "agent_info" or "pane_info" })
      end

      assert.is_true(session:is_running())
    end)
  end

  it("returns false when a Herdr pane disappears", function()
    local errors = {}
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function()
      return failure("agent_not_found", "gone")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(session:is_running())
    assert.are.same({}, errors)
  end)

  it("returns false when the Herdr server is stopped", function()
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function()
      return completed("", 1, "failed to connect to Herdr server: Connection refused\n")
    end

    assert.is_false(session:is_running())
  end)

  it("keeps a session on transient liveness errors instead of detaching it", function()
    local errors = {}
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function(_, opts)
      assert.are.equal(Herdr.LIVENESS_TIMEOUT, opts.timeout)
      return completed("", 1, "permission denied")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_true(session:is_running())
    assert.is_true(session:is_running())
    assert.are.equal(1, #errors)
    assert.matches("Unable to verify", errors[1])
  end)

  it("captures bounded ANSI pane history", function()
    setup_config({ cli = { mux = { backend = "herdr", dump = 123 } } })
    local session = new_session({ started = true, herdr_pane_id = "pane-1", herdr_terminal_id = "term-1" })
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "pane", "read", "pane-1", "--source", "recent", "--lines", "123", "--ansi" }, cmd)
      return completed("\27[31mred\27[0m\n")
    end

    assert.are.equal("\27[31mred\27[0m\n", session:dump())
  end)

  it("keeps persistent Herdr sessions alive on detach", function()
    local calls = 0
    local session = new_session({ started = true, herdr_pane_id = "pane-1", herdr_terminal_id = "term-1" })
    Herdr._run = function()
      calls = calls + 1
      return completed()
    end

    session:detach()

    assert.are.equal(0, calls)
  end)
end)
