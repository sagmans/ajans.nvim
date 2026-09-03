local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local TEST_AGENT_NAME = "ajans-pi-0123456789ab"

local Client = require("ajans.cli.session.herdr.client")
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
  local original_client_run
  local original_client_request
  local original_trusted_socket
  local original_hrtime
  local original_run
  local original_run_async
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
  local original_environ
  local original_defer_fn
  local original_now

  before_each(function()
    original_executable = vim.fn.executable
    original_has = vim.fn.has
    original_system = vim.system
    original_client_run = Client.run
    original_client_request = Client.request
    original_trusted_socket = Client.trusted_socket
    Client.trusted_socket = function()
      return "/tmp/herdr-test.sock"
    end
    original_hrtime = vim.uv.hrtime
    original_run = Herdr._run
    original_run_async = Herdr._run_async
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
    original_environ = vim.fn.environ
    original_defer_fn = vim.defer_fn
    original_now = vim.uv.now
    vim.fn.has = function()
      return 0
    end
    vim.env.HERDR_ENV = nil
    vim.env.HERDR_WORKSPACE_ID = nil
    vim.env.HERDR_TAB_ID = nil
    vim.env.HERDR_PANE_ID = nil
    vim.fn.environ = function()
      return {}
    end
    setup_config({ cli = { mux = { backend = "herdr" } } })
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.has = original_has
    vim.system = original_system
    Client.run = original_client_run
    Client.request = original_client_request
    Client.trusted_socket = original_trusted_socket
    vim.uv.hrtime = original_hrtime
    Herdr._run = original_run
    Herdr._run_async = original_run_async
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
    vim.fn.environ = original_environ
    vim.defer_fn = original_defer_fn
    vim.uv.now = original_now
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("parses and compares semantic versions", function()
    assert.are.same({ 0, 8, 0 }, Herdr.parse_version("herdr 0.8.0"))
    assert.is_false(Herdr.version_at_least({ 0, 7, 3 }))
    assert.is_true(Herdr.version_at_least({ 0, 8, 0 }))
    assert.is_true(Herdr.version_at_least({ 0, 9, 0 }))
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

  it("requires Herdr 0.8.0 or newer", function()
    vim.fn.executable = function(name)
      return name == "herdr" and 1 or 0
    end
    Herdr._run = function()
      return completed("herdr 0.7.3\n")
    end

    local ok, err = Herdr.validate()

    assert.is_false(ok)
    assert.matches("requires `herdr` >= 0.8.0", err)
    assert.matches("found 0.7.3", err)
  end)

  it("returns the validated Herdr version", function()
    vim.fn.executable = function()
      return 1
    end
    Herdr._run = function()
      return completed("herdr 0.8.2\n")
    end

    local ok, err, version = Herdr.validate()

    assert.is_true(ok)
    assert.is_nil(err)
    assert.are.equal("0.8.2", version)
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

  it("routes every sensitive command away from process arguments", function()
    local implementation = fresh_herdr()
    local routed = {}
    Client.run = function(cmd)
      routed[#routed + 1] = vim.deepcopy(cmd)
      return completed("{}\n")
    end
    vim.system = function()
      error("sensitive values must not reach vim.system")
    end
    local commands = {
      { "herdr", "workspace", "create", "--env", "TOKEN=secret" },
      { "herdr", "tab", "create", "--env", "TOKEN=secret" },
      { "herdr", "pane", "split", "--env", "TOKEN=secret" },
      { "herdr", "agent", "start", "ajans-pi-0123456789ab", "--kind", "pi", "--pane", "w1:p2", "--" },
      { "herdr", "pane", "send-text", "pane-1", "secret context" },
    }

    for _, cmd in ipairs(commands) do
      implementation._run(cmd)
    end

    assert.are.same(commands, routed)
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

  it("passes the remaining global deadline to later process-info waits", function()
    local implementation = fresh_herdr()
    local tick = 0
    local waits = {}
    vim.uv.hrtime = function()
      tick = tick + 1
      return tick <= 3 and 0 or 4 * 1e9
    end
    vim.system = function()
      return {
        wait = function(_, timeout)
          waits[#waits + 1] = timeout
          return completed()
        end,
      }
    end

    implementation._run_many({ { "first" }, { "second" } })

    assert.are.same({ implementation.DISCOVERY_TIMEOUT, 1000 }, waits)
  end)

  it("sends Herdr 0.8 API requests through the trusted client", function()
    local observed
    Client.request = function(method, params)
      observed = { method = method, params = vim.deepcopy(params) }
      return success({
        type = "agent_started",
        agent = {
          terminal_id = "term-1",
          pane_id = "w1:p2",
          workspace_id = "w1",
          tab_id = "w1:t1",
        },
      })
    end

    local result = Herdr.api_request("agent.start", {
      name = "ajans-pi-0123456789ab",
      kind = "pi",
      pane_id = "w1:p2",
      args = { "--resume" },
    }, { redact = true })

    assert.are.equal("w1:p2", result.agent.pane_id)
    assert.are.same({
      method = "agent.start",
      params = {
        name = "ajans-pi-0123456789ab",
        kind = "pi",
        pane_id = "w1:p2",
        args = { "--resume" },
      },
    }, observed)
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

  it("delegates detached server startup and waits for bounded readiness only on creation", function()
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
      spawned = { cmd = vim.deepcopy(cmd), opts = opts }
      return {}
    end
    Herdr._wait = function(timeout, predicate, interval)
      waited = { timeout = timeout, interval = interval }
      return predicate()
    end

    assert.is_true(Herdr.ensure_server())
    assert.are.same({ "herdr", "server" }, spawned.cmd)
    assert.is_nil(spawned.opts)
    assert.are.same({ timeout = Herdr.STARTUP_TIMEOUT, interval = Herdr.STARTUP_INTERVAL }, waited)
  end)

  it("preserves a detached server spawn diagnostic", function()
    local errors = {}
    Herdr.validate = function()
      return true
    end
    Herdr.server_status = function()
      return { running = false, compatible = true, restart_needed = false }
    end
    Herdr._spawn = function()
      return false, "permission denied"
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(Herdr.ensure_server())
    assert.matches("permission denied", errors[1])
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

  for _, case in ipairs({
    {
      name = "incompatible protocol",
      status = { running = true, compatible = false, restart_needed = false },
      expected = "incompatible",
    },
  }) do
    it("does not spawn for a " .. case.name, function()
      local spawned = 0
      local waited = 0
      local errors = {}
      Herdr.validate = function()
        return true
      end
      Herdr.server_status = function()
        return case.status
      end
      Herdr._spawn = function()
        spawned = spawned + 1
      end
      Herdr._wait = function()
        waited = waited + 1
      end
      Util.error = function(message)
        errors[#errors + 1] = message
      end

      assert.is_false(Herdr.ensure_server())
      assert.are.equal(0, spawned)
      assert.are.equal(0, waited)
      assert.matches(case.expected, errors[1])
    end)
  end

  it("uses a compatible running server that recommends restart", function()
    local spawned = false
    Herdr.validate = function()
      return true
    end
    Herdr.server_status = function()
      return { running = true, compatible = true, restart_needed = true }
    end
    Herdr._spawn = function()
      spawned = true
    end

    assert.is_true(Herdr.ensure_server())
    assert.is_true(Herdr.is_server_running())
    assert.is_false(spawned)
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

  it("builds Herdr-valid agent names and descriptive session labels", function()
    local first = new_session({ cwd = "/tmp/one", tool = test_tool({ name = "sixteen-char-tool" }) })
    local second = new_session({ cwd = "/tmp/two", tool = test_tool({ name = "sixteen-char-tool" }) })

    assert.matches("^ajans%-sixteen%-char%-[0-9a-f]+$", first:agent_name())
    assert.is_true(#first:agent_name() <= 32)
    assert.matches("^ajans:sixteen%-char%-tool [0-9a-f]+$", first:session_label())
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

  it("waits for a new root pane before starting a registered agent", function()
    local calls = {}
    local agent_start_attempts = 0
    local tool = test_tool({
      name = "pi",
      cmd = { "pi", "--flag" },
      env = { ZED = "last", ALPHA = "first", REMOVE_ME = false },
    })
    local session = new_session({ tool = tool })
    vim.fn.environ = function()
      return {
        ALPHA = "inherited",
        HERDR_PANE_ID = "host-pane",
        PARENT_SECRET = "per-agent-only",
        REMOVE_ME = "old",
      }
    end
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
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        agent_start_attempts = agent_start_attempts + 1
        if agent_start_attempts == 1 then
          return failure("agent_pane_busy", "agent target pane root is not an available shell")
        end
        return success({
          type = "agent_started",
          agent = {
            name = session:agent_name(),
            agent = "pi",
            terminal_id = "term-root",
            pane_id = "root",
            workspace_id = "w1",
            tab_id = "t1",
            cwd = "/tmp/project",
          },
        })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()
    if not attach then
      error("expected terminal attachment", 2)
    end

    assert.are.same({ "herdr", "agent", "attach", "term-root" }, attach.cmd)
    assert.are.equal("herdr term-root", session.id)
    assert.are.equal("herdr:term-root", session.identity)
    assert.are.equal("root", session.herdr_pane_id)
    assert.are.same({}, session.pids)
    assert.is_true(session.started)
    assert.is_false(session.external)
    assert.are.equal(2, agent_start_attempts)
    assert.matches("^[a-z][a-z0-9_-]+$", session:agent_name())
    assert.is_true(#session:agent_name() <= 32)

    local create = assert(find_call(calls, { "herdr", "workspace", "create" })).cmd
    assert_pair(create, "--cwd", "/tmp/project")
    assert_pair(create, "--label", session:session_label())
    assert_pair(create, "--env", "ALPHA=first")
    assert_pair(create, "--env", "PARENT_SECRET=per-agent-only")
    assert_pair(create, "--env", "REMOVE_ME=")
    assert_pair(create, "--env", "ZED=last")
    assert.is_false(vim.tbl_contains(create, "HERDR_PANE_ID=host-pane"))
    assert.is_true(vim.tbl_contains(create, "--no-focus"))
    assert.is_false(vim.tbl_contains(create, "--focus"))

    local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
    assert_pair(start, "--kind", "pi")
    assert_pair(start, "--pane", "root")
    assert.are.same({ "--flag" }, vim.list_slice(start, #start))
    assert.is_nil(find_call(calls, { "herdr", "pane", "close" }))
  end)

  it("starts an unsupported tool through escaped shell input", function()
    local calls = {}
    local tool = test_tool({
      name = "aider",
      cmd = { "aider", "--model", "two words" },
      env = { TOKEN = "secret" },
    })
    local session = new_session({ tool = tool })
    vim.fn.environ = function()
      return { PATH = "/usr/bin" }
    end
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
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "pane" and cmd[3] == "send-text" then
        return success({ type = "pane_send_text" })
      elseif cmd[2] == "pane" and cmd[3] == "send-keys" then
        return completed()
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.are.same({ "herdr", "terminal", "attach", "term-root" }, attach.cmd)
    assert.is_false(session.herdr_agent)
    local create = assert(find_call(calls, { "herdr", "workspace", "create" })).cmd
    assert_pair(create, "--env", "TOKEN=secret")
    local send = assert(find_call(calls, { "herdr", "pane", "send-text" })).cmd
    assert.are.equal("exec 'aider' '--model' 'two words'", send[5])
    assert.is_false(send[5]:find("secret", 1, true) ~= nil)
    assert.are.same({ "herdr", "pane", "send-keys", "root", "enter" }, calls[#calls].cmd)
    assert.is_nil(find_call(calls, { "herdr", "agent", "start" }))
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
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
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

  it("rolls back an isolated workspace when agent identity mismatches its root pane", function()
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
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = { terminal_id = "term-1", pane_id = "agent-pane", workspace_id = "w1", tab_id = "t1" },
        })
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
          root_pane = {
            pane_id = "root",
            terminal_id = "term-root",
            workspace_id = "leaked-workspace",
            tab_id = "t1",
          },
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

  local function existing_agent(session, overrides)
    local agent = {
      name = session:agent_name(),
      agent = "claude",
      terminal_id = "term-existing",
      pane_id = "p-existing",
      workspace_id = "w-existing",
      tab_id = "t-existing",
      cwd = "/tmp/project",
      agent_status = "idle",
    }
    return vim.tbl_extend("force", agent, overrides or {})
  end

  it("reuses an existing named agent instead of creating a second workspace", function()
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" and cmd[3] == "list" then
        return success({ agents = { existing_agent(session) } })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.are.same({ "herdr", "agent", "attach", "term-existing" }, attach.cmd)
    assert.is_true(session.started)
    assert.is_false(session.external)
    assert.are.equal("herdr term-existing", session.id)
    assert.are.equal("herdr:term-existing", session.identity)
    assert.are.equal("p-existing", session.herdr_pane_id)
    assert.are.equal("w-existing", session.herdr_workspace_id)
    assert.are.equal(session:agent_name(), session.herdr_name)
    assert.is_nil(find_call(calls, { "herdr", "workspace", "create" }))
    assert.is_nil(find_call(calls, { "herdr", "agent", "start" }))
    assert.is_nil(find_call(calls, { "herdr", "workspace", "close" }))
  end)

  it("recovers an agent_name_taken race by adopting the winner and closing only the empty workspace", function()
    local calls = {}
    local session = new_session()
    local list_results = {
      success({ agents = {} }),
      success({ agents = { existing_agent(session) } }),
    }
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" and cmd[3] == "list" then
        return table.remove(list_results, 1)
      elseif cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "w1" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return failure("agent_name_taken", "agent name is already used")
      elseif cmd[2] == "workspace" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.are.same({ "herdr", "agent", "attach", "term-existing" }, attach.cmd)
    assert.is_true(session.started)
    assert.are.equal("p-existing", session.herdr_pane_id)
    assert.are.equal("term-existing", session.herdr_terminal_id)
    local closes = vim.tbl_filter(function(call)
      return call.cmd[2] == "workspace" and call.cmd[3] == "close"
    end, calls)
    assert.are.equal(1, #closes)
    assert.are.equal("w1", closes[1].cmd[4])
    assert.is_nil(find_call(calls, { "herdr", "pane", "close" }))
  end)

  for _, case in ipairs({
    { label = "a different agent kind", overrides = { agent = "agy" } },
    { label = "a different working directory", overrides = { cwd = "/other/project" } },
    { label = "unstable resource ids", overrides = { tab_id = vim.NIL } },
  }) do
    it("refuses to reuse a conflicting agent with " .. case.label, function()
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
        calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
        if cmd[2] == "agent" and cmd[3] == "list" then
          return success({ agents = { existing_agent(session, case.overrides) } })
        elseif cmd[2] == "workspace" and cmd[3] == "create" then
          return success({
            type = "workspace_created",
            workspace = { workspace_id = "w1" },
            tab = { tab_id = "t1" },
            root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
          })
        elseif cmd[2] == "agent" and cmd[3] == "start" then
          return failure("agent_name_taken", "agent name is already used")
        elseif cmd[2] == "workspace" and cmd[3] == "close" then
          return completed()
        end
        error("unexpected command: " .. table.concat(cmd, " "))
      end

      assert.is_nil(session:start())

      assert.is_false(session.started == true)
      assert.is_not_nil(find_call(calls, { "herdr", "workspace", "close", "w1" }))
      assert.is_nil(find_call(calls, { "herdr", "pane", "close" }))
      assert.matches("herdr agent get " .. vim.pesc(session:agent_name()), errors[#errors])
    end)
  end

  it("reuses an existing agent from an external tab session without creating resources", function()
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
    Util.info = function(message)
      messages[#messages + 1] = message
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" and cmd[3] == "list" then
        return success({ agents = { existing_agent(session) } })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.is_nil(attach)
    assert.is_true(session.started)
    assert.is_true(session.external)
    assert.are.equal("p-existing", session.herdr_pane_id)
    assert.is_nil(find_call(calls, { "herdr", "tab", "create" }))
    assert.is_nil(find_call(calls, { "herdr", "agent", "start" }))
    assert.is_nil(find_call(calls, { "herdr", "tab", "close" }))
    assert.matches("Reusing", messages[1])
  end)

  it("recovers an agent_name_taken race in an external tab by closing only the empty tab", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "window" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    local calls = {}
    local messages = {}
    local session = new_session()
    local list_results = {
      success({ agents = {} }),
      success({ agents = { existing_agent(session) } }),
    }
    Herdr.ensure_server = function()
      return true
    end
    Util.info = function(message)
      messages[#messages + 1] = message
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" and cmd[3] == "list" then
        return table.remove(list_results, 1)
      elseif cmd[2] == "tab" and cmd[3] == "create" then
        return success({
          type = "tab_created",
          tab = { tab_id = "new-tab", workspace_id = "host-workspace" },
          root_pane = {
            pane_id = "tab-root",
            terminal_id = "term-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return failure("agent_name_taken", "agent name is already used")
      elseif cmd[2] == "tab" and cmd[3] == "close" then
        return completed()
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.is_nil(attach)
    assert.is_true(session.started)
    assert.are.equal("p-existing", session.herdr_pane_id)
    local closes = vim.tbl_filter(function(call)
      return call.cmd[2] == "tab" and call.cmd[3] == "close"
    end, calls)
    assert.are.equal(1, #closes)
    assert.are.equal("new-tab", closes[1].cmd[4])
    assert.matches("Reusing", messages[1])
  end)

  it("reuses an existing agent from an external split session without splitting", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split", split = { vertical = true, size = 0.5 } } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    vim.env.HERDR_PANE_ID = "host-pane"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Util.info = function() end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "agent" and cmd[3] == "list" then
        return success({ agents = { existing_agent(session) } })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    local attach = session:start()

    assert.is_nil(attach)
    assert.is_true(session.started)
    assert.are.equal("p-existing", session.herdr_pane_id)
    assert.is_nil(find_call(calls, { "herdr", "pane", "split" }))
    assert.is_nil(find_call(calls, { "herdr", "agent", "start" }))
    assert.is_nil(find_call(calls, { "herdr", "pane", "close" }))
  end)

  it("advises once when the Herdr integration for the started tool is missing", function()
    local Integrations = require("ajans.cli.session.herdr.integrations")
    Integrations.reset()
    local original_warn = Util.warn
    local warnings = {}
    Util.warn = function(message)
      warnings[#warnings + 1] = message
    end
    local session = new_session({ tool = test_tool({ name = "pi", cmd = { "pi" } }) })
    Herdr.ensure_server = function()
      return true
    end
    Util.error = function() end
    Herdr._run = function(cmd)
      if cmd[2] == "integration" and cmd[3] == "status" then
        return completed("pi: not installed (/hooks)\n", 0)
      elseif cmd[2] == "agent" and cmd[3] == "list" then
        return success({ agents = {} })
      elseif cmd[2] == "workspace" and cmd[3] == "create" then
        return success({
          type = "workspace_created",
          workspace = { workspace_id = "w1" },
          tab = { tab_id = "t1" },
          root_pane = { pane_id = "root", terminal_id = "term-root", workspace_id = "w1", tab_id = "t1" },
        })
      elseif cmd[2] == "agent" then
        return failure("agent_start_failed", "spawn failed")
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end

    session:start()
    session:start()

    assert.are.equal(1, #warnings)
    assert.matches("herdr integration install pi", warnings[1])
    Util.warn = original_warn
    Integrations.reset()
  end)

  it("creates a Herdr tab and starts the agent in its root pane", function()
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
          root_pane = {
            pane_id = "tab-root",
            terminal_id = "term-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-window",
            pane_id = "tab-root",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    Util.info = function() end

    local attach = session:start()

    assert.is_nil(attach)
    assert.is_true(session.external)
    local create = assert(find_call(calls, { "herdr", "tab", "create" })).cmd
    assert_pair(create, "--workspace", "host-workspace")
    assert_pair(create, "--label", session:session_label())
    assert.is_true(vim.tbl_contains(create, "--focus"))
    assert.is_false(vim.tbl_contains(create, "--no-focus"))
    local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
    assert_pair(start, "--kind", "claude")
    assert_pair(start, "--pane", "tab-root")
    assert.is_nil(find_call(calls, { "herdr", "pane", "close" }))
  end)

  it("keeps focus on the host tab when creating a tab with focus disabled", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "window", focus = false } } })
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
          root_pane = {
            pane_id = "tab-root",
            terminal_id = "term-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-window",
            pane_id = "tab-root",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
        })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    Util.info = function() end

    session:start()

    local create = assert(find_call(calls, { "herdr", "tab", "create" })).cmd
    assert.is_true(vim.tbl_contains(create, "--no-focus"))
    assert.is_false(vim.tbl_contains(create, "--focus"))
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
          root_pane = {
            pane_id = "tab-root",
            terminal_id = "term-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
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

  it("rolls back a new tab when agent identity mismatches its root pane", function()
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
          root_pane = {
            pane_id = "tab-root",
            terminal_id = "term-window",
            workspace_id = "host-workspace",
            tab_id = "new-tab",
          },
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
      final_pane = { x = 36, y = 0, width = 84, height = 40 },
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
      final_pane = { x = 80, y = 0, width = 20, height = 40 },
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
      final_pane = { x = 0, y = 30, width = 100, height = 10 },
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
      vim.env.HERDR_PANE_ID = "host-pane"
      local calls = {}
      local session = new_session()
      Herdr.ensure_server = function()
        return true
      end
      Herdr._run = function(cmd)
        calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
        if cmd[2] == "pane" and cmd[3] == "split" then
          return success({
            type = "pane_split",
            pane = {
              terminal_id = "term-split",
              pane_id = "pane-split",
              workspace_id = "host-workspace",
              tab_id = "host-tab",
            },
          })
        elseif cmd[2] == "agent" and cmd[3] == "start" then
          return success({
            type = "agent_started",
            agent = {
              terminal_id = "term-split",
              pane_id = "pane-split",
              workspace_id = "host-workspace",
              tab_id = "host-tab",
            },
          })
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
                panes = { { pane_id = "pane-split", rect = case.final_pane } },
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

      local split = assert(find_call(calls, { "herdr", "pane", "split" })).cmd
      assert_pair(split, "--pane", "host-pane")
      assert_pair(split, "--direction", case.split)
      assert.is_true(vim.tbl_contains(split, "--focus"))
      assert.is_false(vim.tbl_contains(split, "--no-focus"))
      local start = assert(find_call(calls, { "herdr", "agent", "start" })).cmd
      assert_pair(start, "--pane", "pane-split")
      local resize = assert(find_call(calls, { "herdr", "pane", "resize" })).cmd
      assert_pair(resize, "--pane", "pane-split")
      assert_pair(resize, "--direction", case.resize_direction)
      assert_pair(resize, "--amount", case.amount)
    end)
  end

  it("keeps focus on the host pane when creating a split with focus disabled", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split", focus = false } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    vim.env.HERDR_PANE_ID = "host-pane"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "pane" and cmd[3] == "split" then
        return success({
          type = "pane_split",
          pane = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "agent" and cmd[3] == "start" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "pane" and cmd[3] == "layout" then
        return success({
          type = "pane_layout",
          layout = {
            area = { x = 0, y = 0, width = 200, height = 80 },
            panes = { { pane_id = "pane-split", rect = { x = 100, y = 0, width = 100, height = 80 } } },
            splits = {
              {
                id = "outer",
                direction = "down",
                ratio = 0.5,
                rect = { x = 0, y = 0, width = 200, height = 80 },
              },
              {
                id = "immediate",
                direction = "right",
                ratio = 0.5,
                rect = { x = 0, y = 0, width = 200, height = 80 },
              },
            },
          },
        })
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    Util.info = function() end

    assert.is_nil(session:start())

    local split = assert(find_call(calls, { "herdr", "pane", "split" })).cmd
    assert.is_true(vim.tbl_contains(split, "--no-focus"))
    assert.is_false(vim.tbl_contains(split, "--focus"))
  end)
  for _, case in ipairs({
    { name = "already-sized no-op", size = 0.5, resize = nil, expected = true },
    {
      name = "changed=false response",
      size = 0.7,
      resize = {
        changed = false,
        layout = {
          panes = { { pane_id = "pane-split", rect = { x = 30, y = 0, width = 70, height = 40 } } },
          splits = {
            { id = "immediate", direction = "right", ratio = 0.3, rect = { x = 0, y = 0, width = 100, height = 40 } },
          },
        },
      },
      expected = false,
    },
    { name = "partial resize response", size = 0.7, resize = { changed = true }, expected = false },
  }) do
    it("handles a " .. case.name, function()
      setup_config({ cli = { mux = { backend = "herdr", split = { size = case.size } } } })
      local resize_calls = 0
      local session = new_session()
      Herdr._run = function(cmd)
        if cmd[3] == "layout" then
          return success({
            layout = {
              panes = { { pane_id = "pane-split", rect = { x = 50, y = 0, width = 50, height = 40 } } },
              splits = {
                {
                  id = "immediate",
                  direction = "right",
                  ratio = 0.5,
                  rect = { x = 0, y = 0, width = 100, height = 40 },
                },
              },
            },
          })
        elseif cmd[3] == "resize" then
          resize_calls = resize_calls + 1
          return success({ resize = case.resize })
        end
        error("unexpected command")
      end
      Util.error = function() end

      assert.are.equal(case.expected, session:size_split("pane-split", "right"))
      assert.are.equal(case.resize and 1 or 0, resize_calls)
    end)
  end

  it("targets an inner split through its sibling pane", function()
    setup_config({ cli = { mux = { backend = "herdr", split = { size = 0.2 } } } })
    local resize_command
    local session = new_session()
    Herdr._run = function(cmd)
      if cmd[3] == "layout" then
        return success({
          layout = {
            panes = {
              { pane_id = "sibling", rect = { x = 0, y = 0, width = 25, height = 40 } },
              { pane_id = "pane-split", rect = { x = 25, y = 0, width = 25, height = 40 } },
              { pane_id = "outer-sibling", rect = { x = 50, y = 0, width = 50, height = 40 } },
            },
            splits = {
              { id = "outer", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
              { id = "immediate", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 50, height = 40 } },
            },
          },
        })
      elseif cmd[3] == "resize" then
        resize_command = vim.deepcopy(cmd)
        return success({
          resize = {
            changed = true,
            layout = {
              panes = {
                { pane_id = "sibling", rect = { x = 0, y = 0, width = 40, height = 40 } },
                { pane_id = "pane-split", rect = { x = 40, y = 0, width = 10, height = 40 } },
                { pane_id = "outer-sibling", rect = { x = 50, y = 0, width = 50, height = 40 } },
              },
              splits = {
                { id = "outer", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
                {
                  id = "immediate",
                  direction = "right",
                  ratio = 0.8,
                  rect = { x = 0, y = 0, width = 50, height = 40 },
                },
              },
            },
          },
        })
      end
      error("unexpected command")
    end

    assert.is_true(session:size_split("pane-split", "right"))
    assert_pair(resize_command, "--pane", "sibling")
    assert_pair(resize_command, "--direction", "right")
  end)

  it("rejects malformed layout geometry before resizing", function()
    local calls = 0
    local errors = {}
    local session = new_session()
    Herdr._run = function(cmd)
      calls = calls + 1
      assert.are.equal("layout", cmd[3])
      return success({
        layout = {
          panes = { { pane_id = "pane-split", rect = { x = 0, y = 0, height = 40 } } },
          splits = {},
        },
      })
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(session:size_split("pane-split", "right"))
    assert.are.equal(1, calls)
    assert.matches("invalid", errors[1])
  end)

  it("rolls back after a malformed resize layout", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split", split = { size = 0.8 } } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    vim.env.HERDR_PANE_ID = "host-pane"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "pane" and cmd[3] == "split" then
        return success({
          type = "pane_split",
          pane = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[3] == "layout" then
        return success({
          type = "pane_layout",
          layout = {
            panes = { { pane_id = "pane-split", rect = { x = 50, y = 0, width = 50, height = 40 } } },
            splits = {
              { id = "immediate", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
            },
          },
        })
      elseif cmd[3] == "resize" then
        return success({
          type = "pane_resize",
          resize = {
            changed = true,
            layout = {
              panes = { { pane_id = "pane-split", rect = { x = 10, y = 0, width = 90, height = 40 } } },
              splits = {
                { id = "immediate", direction = "right", ratio = 0.1, rect = { x = 0, y = 0, height = 40 } },
              },
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
            { id = "immediate", direction = "right", ratio = 0.5, rect = { x = 0, y = 0, width = 100, height = 40 } },
          },
        },
      })
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    assert.is_false(session:size_split("pane-split", "right"))
    assert.are.equal(1, #calls)
    assert.matches("outside the supported", errors[1])
  end)

  it("closes a pane returned by a malformed split response", function()
    setup_config({ cli = { mux = { backend = "herdr", create = "split" } } })
    vim.env.HERDR_ENV = "1"
    vim.env.HERDR_WORKSPACE_ID = "host-workspace"
    vim.env.HERDR_TAB_ID = "host-tab"
    vim.env.HERDR_PANE_ID = "host-pane"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "pane" and cmd[3] == "split" then
        return success({
          type = "pane_split",
          pane = {
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
    vim.env.HERDR_PANE_ID = "host-pane"
    local calls = {}
    local session = new_session()
    Herdr.ensure_server = function()
      return true
    end
    Herdr._run = function(cmd)
      calls[#calls + 1] = { cmd = vim.deepcopy(cmd) }
      if cmd[2] == "pane" and cmd[3] == "split" then
        return success({
          type = "pane_split",
          pane = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
      elseif cmd[2] == "agent" then
        return success({
          type = "agent_started",
          agent = {
            terminal_id = "term-split",
            pane_id = "pane-split",
            workspace_id = "host-workspace",
            tab_id = "host-tab",
          },
        })
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

  it("refuses terminal attachment through an untrusted socket", function()
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Client.trusted_socket = function()
      return nil, "unsafe socket"
    end
    Util.error = function() end

    local cmd, accepted = session:attach()
    assert.is_nil(cmd)
    assert.is_false(accepted)
  end)

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
      return cmd[2] == "pane" and cmd[3] == "send-text" and success({ type = "ok" }) or completed()
    end

    session:send("first\nsecond")
    session:send("third")
    session:submit()

    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "escape", "[", "I" }, calls[1])
    assert.are.same({ "herdr", "pane", "send-text", "pane-1", "first\nsecond" }, calls[2])
    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "escape", "[", "I" }, calls[3])
    assert.are.same({ "herdr", "pane", "send-text", "pane-1", "third" }, calls[4])
    assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "enter" }, calls[5])
  end)

  it("keeps reentrant text and submission operations ordered", function()
    local calls = {}
    local nested = false
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function(cmd)
      if cmd[2] == "pane" and cmd[3] == "send-text" then
        calls[#calls + 1] = "begin:" .. cmd[5]
        if not nested then
          nested = true
          session:send("second")
          session:submit()
        end
        calls[#calls + 1] = "end:" .. cmd[5]
        return success({ type = "ok" })
      end
      calls[#calls + 1] = "key:" .. cmd[#cmd]
      return completed()
    end

    assert.is_true(session:send("first"))

    assert.are.same({ "begin:first", "end:first", "begin:second", "end:second", "key:enter" }, calls)
    assert.is_false(session._sending)
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
      if cmd[2] == "pane" and cmd[3] == "send-text" then
        if failed then
          failed = false
          return failure("pane_send_failed", "gone")
        end
        return success({ type = "ok" })
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

  it("targets a managed agent by name for input authorization", function()
    local tool = test_tool({ name = "pi", cmd = { "pi" } })
    tool.is_proc = function(_, proc)
      return proc.cmd == "pi"
    end
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = tool,
    })
    session.herdr_name = TEST_AGENT_NAME
    Herdr._run = function(cmd)
      if cmd[2] == "agent" then
        assert.are.same({ "herdr", "agent", "get", TEST_AGENT_NAME }, cmd)
        return success({
          agent = {
            terminal_id = "term-1",
            pane_id = "pane-1",
            name = TEST_AGENT_NAME,
          },
        })
      end
      return success({ process_info = { foreground_processes = { { pid = 42, cmdline = "pi" } } } })
    end

    assert.is_true(session:accepts_automated_input())
  end)

  it("authorizes the launched tool after its bootstrap process exits", function()
    local tool = test_tool({ name = "pi", cmd = { "pi" } })
    tool.is_proc = function(_, proc)
      return proc.cmd == "pi"
    end
    local session = new_session({ tool = tool })
    local phase = "bootstrap"
    Herdr._run = function(cmd)
      if cmd[2] == "agent" and cmd[3] == "get" then
        return success({ agent = { terminal_id = "term-1", pane_id = "pane-1", name = session.herdr_name } })
      end
      assert.are.same({ "herdr", "pane", "process-info", "--pane", "pane-1" }, cmd)
      if phase == "bootstrap" then
        return success({
          process_info = { shell_pid = 100, foreground_processes = { { pid = 101, cmdline = "zsh" } } },
        })
      end
      return success({ process_info = { shell_pid = 100, foreground_processes = { { pid = 200, cmdline = "pi" } } } })
    end

    session:set_agent({
      terminal_id = "term-1",
      pane_id = "pane-1",
      workspace_id = "workspace-1",
      tab_id = "tab-1",
    }, "split")
    local deferred
    local accepted
    vim.uv.now = function()
      return 0
    end
    vim.defer_fn = function(callback)
      deferred = callback
      return 1
    end

    session:authorize_automated_input(function(value)
      accepted = value
    end)
    assert.is_nil(accepted)
    assert.is_function(deferred)

    phase = "ready"
    deferred()
    assert.is_true(accepted)
    assert.are.equal(200, session._authorized_pid)
  end)

  local function ready_gated_session(dump)
    local tool = test_tool({ name = "antigravity", cmd = { "agy" } })
    tool.is_proc = function(_, proc)
      return proc.cmd == "agy"
    end
    tool.mux_ready = {
      required = { "? for shortcuts" },
      blocked = { "Do you trust the contents of this project" },
    }
    local session = new_session({
      tool = tool,
      started = true,
      herdr_agent = false,
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function(cmd)
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ process_info = { foreground_processes = { { pid = 200, cmdline = "agy" } } } })
      elseif cmd[2] == "pane" and cmd[3] == "read" then
        if dump == nil then
          return completed("", 1, "pane vanished")
        end
        return completed(dump)
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    return session
  end

  for _, case in ipairs({
    {
      label = "while the tool shows a boot splash",
      dump = "Welcome to the Antigravity CLI.\n Signing in...",
      expected = false,
    },
    {
      label = "while the tool shows the folder trust dialog",
      dump = "Do you trust the contents of this project?\n> Yes, I trust this folder",
      expected = false,
    },
    {
      label = "when a blocked screen also contains the ready footer",
      dump = "Do you trust the contents of this project?\n? for shortcuts",
      expected = false,
    },
    {
      label = "once the tool shows its input footer",
      dump = "Antigravity CLI 1.1.25\n> Accept-edits mode\n? for shortcuts",
      expected = true,
    },
    { label = "when the pane screen cannot be read", dump = nil, expected = false },
  }) do
    it("holds automated input " .. case.label, function()
      local session = ready_gated_session(case.dump)

      assert.are.equal(case.expected, session:accepts_automated_input())
    end)
  end

  it("waits for a settling screen instead of typing into it", function()
    local tool = test_tool({ name = "antigravity", cmd = { "agy" } })
    tool.is_proc = function(_, proc)
      return proc.cmd == "agy"
    end
    tool.mux_ready = { required = { "? for shortcuts" } }
    local session = new_session({
      tool = tool,
      started = true,
      herdr_agent = false,
      herdr_pane_id = "pane-1",
    })
    session.fresh = true
    local phase = "booting"
    Herdr._run = function(cmd)
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ process_info = { foreground_processes = { { pid = 200, cmdline = "agy" } } } })
      elseif cmd[2] == "pane" and cmd[3] == "read" then
        if phase == "booting" then
          return completed("Welcome to the Antigravity CLI.\n Signing in...")
        end
        return completed("Antigravity CLI 1.1.25\n? for shortcuts")
      end
      error("unexpected command: " .. table.concat(cmd, " "))
    end
    local deferred
    local accepted
    vim.uv.now = function()
      return 0
    end
    vim.defer_fn = function(callback)
      deferred = callback
      return 1
    end

    session:authorize_automated_input(function(value)
      accepted = value
    end)
    assert.is_nil(accepted)

    phase = "ready"
    deferred()
    assert.is_true(accepted)
  end)

  it("skips the screen gate for tools without readiness markers", function()
    local tool = test_tool({ name = "pi", cmd = { "pi" } })
    tool.is_proc = function(_, proc)
      return proc.cmd == "pi"
    end
    local session = new_session({
      tool = tool,
      started = true,
      herdr_agent = false,
      herdr_pane_id = "pane-1",
    })
    Herdr._run = function(cmd)
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ process_info = { foreground_processes = { { pid = 200, cmdline = "pi" } } } })
      end
      error("screen reads must not happen without markers: " .. table.concat(cmd, " "))
    end

    assert.is_true(session:accepts_automated_input())
  end)

  it("times out fresh authorization exactly once", function()
    local tool = test_tool({ name = "pi", cmd = { "pi" } })
    tool.is_proc = function()
      return false
    end
    local session = new_session({
      tool = tool,
      fresh = true,
      herdr_agent = false,
      herdr_pane_id = "pane-1",
    })
    session.fresh = true
    Herdr._run = function()
      return success({ process_info = { foreground_processes = { { pid = 100, cmdline = "zsh" } } } })
    end
    local now = 0
    local deferred
    local schedules = 0
    local callbacks = 0
    local accepted
    vim.uv.now = function()
      return now
    end
    vim.defer_fn = function(callback)
      schedules = schedules + 1
      deferred = callback
      return schedules
    end

    session:authorize_automated_input(function(value)
      callbacks = callbacks + 1
      accepted = value
    end)
    assert.is_nil(accepted)
    now = Herdr.INPUT_READY_TIMEOUT
    deferred()

    assert.is_false(accepted)
    assert.is_false(session.fresh)
    assert.are.equal(1, callbacks)
    assert.are.equal(1, schedules)
  end)

  it("reports a readiness matcher exception without retrying", function()
    local reports = {}
    local tool = test_tool({ name = "pi", cmd = { "pi" } })
    tool.is_proc = function()
      error("broken matcher")
    end
    local session = new_session({
      tool = tool,
      fresh = true,
      herdr_agent = false,
      herdr_pane_id = "pane-1",
    })
    session.fresh = true
    Herdr._run = function()
      return success({ process_info = { foreground_processes = { { pid = 100, cmdline = "pi" } } } })
    end
    Util.error = function(message)
      reports[#reports + 1] = message
    end
    local deferred = false
    vim.defer_fn = function()
      deferred = true
      return 1
    end
    local accepted

    session:authorize_automated_input(function(value)
      accepted = value
    end)

    assert.is_false(accepted)
    assert.is_false(session.fresh)
    assert.is_false(deferred)
    assert.are.equal(1, #reports)
    assert.matches("broken matcher", reports[1])
  end)

  for _, case in ipairs({
    { name = "transport error", response = completed("", 124, "timed out"), expected = false },
    { name = "malformed response", response = completed("not-json"), expected = false },
    {
      name = "mismatched identity",
      response = success({ agent = { terminal_id = "other", pane_id = "pane-1" } }),
      expected = false,
    },
    {
      name = "matching identity",
      response = success({ agent = { terminal_id = "term-1", pane_id = "pane-1" } }),
      expected = true,
    },
  }) do
    it("authorizes agent input only after a " .. case.name, function()
      local tool = test_tool()
      tool.is_proc = function(_, proc)
        return proc.cmd == "claude"
      end
      local session = new_session({
        started = true,
        herdr_agent = true,
        herdr_terminal_id = "term-1",
        herdr_pane_id = "pane-1",
        tool = tool,
      })
      Herdr._run = function(cmd)
        if cmd[2] == "pane" then
          return success({ process_info = { foreground_processes = { { pid = 42, cmdline = "claude" } } } })
        end
        assert.are.same({ "herdr", "agent", "get", "term-1" }, cmd)
        return case.response
      end

      assert.are.equal(case.expected, session:accepts_automated_input())
    end)
  end

  it("refuses a replaced agent or foreground process", function()
    local tool = test_tool()
    tool.is_proc = function(_, proc)
      return proc.cmd == "claude"
    end
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = tool,
    })
    session.herdr_name = "ajans:claude expected"
    session.herdr_label = "claude"
    session.herdr_agent_session = { source = "claude", value = "session-1" }
    local name = "other"
    local pids = { 42 }
    local start_time = "start-1"
    Herdr._run = function(cmd)
      if cmd[2] == "agent" then
        return success({
          agent = {
            terminal_id = "term-1",
            pane_id = "pane-1",
            name = name,
            agent = "claude",
            agent_session = { source = "claude", value = "session-1" },
          },
        })
      end
      return success({
        process_info = {
          foreground_processes = vim.tbl_map(function(pid)
            return { pid = pid, cmdline = "claude", name = "claude", start_time = start_time }
          end, pids),
        },
      })
    end

    assert.is_false(session:accepts_automated_input())
    name = session.herdr_name
    assert.is_true(session:accepts_automated_input())
    start_time = "start-2"
    assert.is_false(session:accepts_automated_input())
    start_time = "start-1"
    pids = { 43, 42 }
    assert.is_true(session:accepts_automated_input())
    pids = { 43 }
    assert.is_false(session:accepts_automated_input())
  end)

  it("revalidates the pinned process before delivering queued input", function()
    local tool = test_tool()
    tool.is_proc = function(_, proc)
      return proc.cmd == "claude"
    end
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = tool,
    })
    local start_time = "start-1"
    local sends = 0
    Herdr._run = function(cmd)
      if cmd[2] == "agent" and cmd[3] == "get" then
        return success({ agent = { terminal_id = "term-1", pane_id = "pane-1" } })
      end
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({
          process_info = {
            foreground_processes = {
              { pid = 42, cmdline = "claude", name = "claude", start_time = start_time },
            },
          },
        })
      end
      sends = sends + 1
      return completed()
    end

    assert.is_true(session:accepts_automated_input())
    start_time = "start-2"
    assert.is_false(session:send("secret"))
    assert.are.equal(0, sends)
  end)

  it("refuses submit when a pinned PID is reused", function()
    local tool = test_tool()
    tool.is_proc = function(_, proc)
      return proc.cmd == "claude"
    end
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = tool,
    })
    local start_time = "start-1"
    local sends = 0
    local enters = 0
    Herdr._run = function(cmd)
      if cmd[2] == "agent" and cmd[3] == "get" then
        return success({ agent = { terminal_id = "term-1", pane_id = "pane-1" } })
      end
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({
          process_info = {
            foreground_processes = {
              { pid = 42, cmdline = "claude", name = "claude", start_time = start_time },
            },
          },
        })
      end
      if cmd[2] == "pane" and cmd[3] == "send-keys" then
        enters = enters + 1
      else
        sends = sends + 1
      end
      return success({})
    end

    assert.is_true(session:accepts_automated_input())
    assert.is_true(session:send("safe"))
    start_time = "start-2"
    assert.is_false(session:submit())
    assert.are.equal(1, sends)
    assert.are.equal(0, enters)
  end)

  it("stops a chunked send when the pinned process changes", function()
    local tool = test_tool()
    tool.is_proc = function(_, proc)
      return proc.cmd == "claude"
    end
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
      tool = tool,
    })
    local pid = 42
    local sends = 0
    Herdr._run = function(cmd)
      if cmd[2] == "agent" and cmd[3] == "get" then
        return success({ agent = { terminal_id = "term-1", pane_id = "pane-1" } })
      end
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ process_info = { foreground_processes = { { pid = pid, cmdline = "claude" } } } })
      end
      sends = sends + 1
      pid = 43
      return success({})
    end

    assert.is_true(session:accepts_automated_input())
    assert.is_false(session:send(string.rep("x", Herdr.SEND_CHUNK_BYTES + 1)))
    assert.are.equal(1, sends)
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

  it("releases the input queue after a matcher exception", function()
    local reports = {}
    local throws = true
    local sends = 0
    local tool = test_tool({ name = "custom" })
    tool.is_proc = function()
      if throws then
        throws = false
        error("matcher failed")
      end
      return true
    end
    local session = new_session({
      started = true,
      herdr_agent = false,
      herdr_terminal_id = "term-custom",
      herdr_pane_id = "pane-custom",
      tool = tool,
      _authorized_pid = 42,
    })
    session._authorized_pid = 42
    Herdr._run = function(cmd)
      if cmd[2] == "pane" and cmd[3] == "process-info" then
        return success({ process_info = { foreground_processes = { { pid = 42, cmdline = "custom" } } } })
      end
      sends = sends + 1
      return success({ type = "ok" })
    end
    Util.error = function(message)
      reports[#reports + 1] = message
    end

    assert.is_false(session:send("first"))
    assert.is_false(session._sending)
    assert.are.same({}, session._input_queue)
    assert.is_true(session:send("second"))

    assert.are.equal(1, sends)
    assert.are.equal(1, #reports)
    assert.matches("matcher failed", reports[1])
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
      return failure("pane_send_failed", "gone")
    end
    Util.error = function() end

    assert.is_false(session:send("partial"))
    assert.is_false(session:submit())
    assert.are.equal(1, #calls)
    assert.are.same({ "herdr", "pane", "send-text", "pane-1", "partial" }, calls[1])
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
    local secret = string.rep("a", Herdr.SEND_CHUNK_BYTES - 1) .. "€secret"
    Herdr._run = function(cmd)
      calls[#calls + 1] = vim.deepcopy(cmd)
      return #calls == 1 and success({ type = "ok" }) or failure("agent_send_failed", "gone")
    end
    Util.error = function(message)
      errors[#errors + 1] = message
    end

    session:send(secret)

    assert.are.equal(2, #calls)
    assert.are.equal(Herdr.SEND_CHUNK_BYTES - 1, #calls[1][5])
    assert.matches("^€", calls[2][5])
    assert.is_true(pcall(vim.str_utfindex, calls[1][5]))
    assert.is_true(pcall(vim.str_utfindex, calls[2][5]))
    assert.are.equal(secret, calls[1][5] .. calls[2][5])
    assert.is_false(errors[1]:find("secret", 1, true) ~= nil)
    assert.matches("<redacted>", errors[1])
  end)

  it("targets a managed agent by name for liveness", function()
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    session.herdr_name = TEST_AGENT_NAME
    Herdr._run = function(cmd)
      assert.are.same({ "herdr", "agent", "get", TEST_AGENT_NAME }, cmd)
      return success({ type = "agent_info" })
    end

    assert.is_true(session:is_running())
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

  it("checks Herdr liveness without blocking scheduled status refresh", function()
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    local running
    Herdr._run_async = function(cmd, opts, callback)
      assert.are.same({ "herdr", "agent", "get", "term-1" }, cmd)
      assert.are.equal(Herdr.LIVENESS_TIMEOUT, opts.timeout)
      callback(success({ type = "agent_info" }))
    end

    session:is_running_async(function(value)
      running = value
    end)

    vim.wait(100, function()
      return running ~= nil
    end)
    assert.is_true(running)
  end)

  for _, case in ipairs({
    { name = "missing agent", response = failure("agent_not_found", "gone") },
    { name = "stopped server", response = completed("", 1, "failed to connect to Herdr server: Connection refused") },
  }) do
    it("reports asynchronous liveness false for a " .. case.name, function()
      local session = new_session({
        started = true,
        herdr_agent = true,
        herdr_terminal_id = "term-1",
        herdr_pane_id = "pane-1",
      })
      local running
      Herdr._run_async = function(_, _, callback)
        callback(case.response)
      end

      session:is_running_async(function(value)
        running = value
      end)

      vim.wait(100, function()
        return running ~= nil
      end)
      assert.is_false(running)
    end)
  end

  it("completes asynchronous liveness when process spawning fails", function()
    local session = new_session({
      started = true,
      herdr_agent = true,
      herdr_terminal_id = "term-1",
      herdr_pane_id = "pane-1",
    })
    local running
    Herdr._run_async = function()
      error("EACCES")
    end
    Util.error = function() end

    session:is_running_async(function(value)
      running = value
    end)

    vim.wait(100, function()
      return running ~= nil
    end)
    assert.is_true(running)
  end)

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

  it("applies Herdr's scrollback limit without changing shared config", function()
    setup_config({ cli = { mux = { backend = "herdr", dump = 5000 } } })
    local session = new_session({ started = true, herdr_pane_id = "pane-1", herdr_terminal_id = "term-1" })
    Herdr._run = function(cmd)
      assert.are.same({
        "herdr",
        "pane",
        "read",
        "pane-1",
        "--source",
        "recent",
        "--lines",
        tostring(Herdr.MAX_DUMP_LINES),
        "--ansi",
      }, cmd)
      return completed("history\n")
    end

    assert.are.equal("history\n", session:dump())
    assert.are.equal(5000, Config.cli.mux.dump)
  end)

  it("applies Herdr's minimum scrollback without changing shared config", function()
    setup_config({ cli = { mux = { backend = "herdr", dump = 0 } } })
    local session = new_session({ started = true, herdr_pane_id = "pane-1", herdr_terminal_id = "term-1" })
    Herdr._run = function(cmd)
      assert_pair(cmd, "--lines", "1")
      return completed("history\n")
    end

    assert.are.equal("history\n", session:dump())
    assert.are.equal(0, Config.cli.mux.dump)
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
