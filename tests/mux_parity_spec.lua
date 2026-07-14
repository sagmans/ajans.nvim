---@module 'luassert'

local Client = require("ajans.cli.session.herdr.client")
local Config = require("ajans.config")
local Herdr = require("ajans.cli.session.herdr")
local Procs = require("ajans.cli.procs")
local Scrollback = require("ajans.cli.scrollback")
local Tmux = require("ajans.cli.session.tmux")
local Util = require("ajans.util")

local function completed(stdout, code, stderr)
  return { code = code or 0, signal = 0, stdout = stdout or "", stderr = stderr or "" }
end

local function success(result)
  return completed(vim.json.encode({ id = "contract", result = result }) .. "\n")
end

local function setup_config(backend, mux)
  pcall(vim.api.nvim_del_user_command, "Ajans")
  Config.setup({
    cli = {
      mux = vim.tbl_deep_extend("force", { backend = backend, dump = 25 }, mux or {}),
      tools = {
        contract = {
          cmd = { "contract-agent" },
          is_proc = function(_, proc)
            return proc.cmd:find("contract%-agent") ~= nil
          end,
        },
      },
    },
  })
end

local function direct_tool(opts)
  opts = opts or {}
  return {
    name = opts.name or "contract",
    cmd = opts.cmd or { "contract-agent", "--flag" },
    env = opts.env or {},
    mux_focus = opts.mux_focus,
    is_proc = function(_, proc)
      return proc.cmd == "contract-agent"
    end,
  }
end

local function tmux_session(opts)
  opts = opts or {}
  return setmetatable({
    sid = "contract abc123",
    id = "contract abc123",
    cwd = "/tmp/contract",
    mux_session = opts.external and "other" or "contract abc123",
    tmux_pane_id = "%1",
    tmux_pid = 101,
    tool = direct_tool({ mux_focus = opts.mux_focus, env = opts.env }),
    started = opts.started,
    external = opts.external,
  }, Tmux)
end

local function herdr_session(opts)
  opts = opts or {}
  return setmetatable({
    sid = "contract abc123",
    id = "herdr term-1",
    identity = "herdr:term-1",
    cwd = "/tmp/contract",
    herdr_agent = opts.agent ~= false,
    herdr_terminal_id = "term-1",
    herdr_pane_id = "pane-1",
    herdr_workspace_id = "workspace-1",
    herdr_tab_id = "tab-1",
    herdr_placement = opts.external and "tab" or "workspace",
    tool = direct_tool({ mux_focus = opts.mux_focus, env = opts.env }),
    started = opts.started,
    external = opts.external,
  }, Herdr)
end

local function tmux_discovery()
  Tmux.panes = function()
    return {
      {
        state_id = "tmux 101",
        id = "%1",
        pid = 101,
        session_name = "contract abc123",
        session_id = "$1",
        cwd = "/tmp/pane",
      },
    }
  end
  Tmux.clients = function()
    return { ["$1"] = { 103 } }
  end
  Procs.new = function()
    return {
      walk = function(_, _, callback)
        callback({ pid = 102, ppid = 101, cmd = "contract-agent --flag", cwd = "/tmp/contract" })
      end,
    }
  end
  Procs.pids = function()
    return { 101, 102 }
  end
  return Tmux.sessions()
end

local function herdr_discovery(custom)
  Herdr.supports_snapshot = function()
    return true
  end
  Herdr._run = function(cmd)
    assert.are.same({ "herdr", "api", "snapshot" }, cmd)
    return success({
      type = "session_snapshot",
      snapshot = {
        workspaces = { { workspace_id = "workspace-1", label = custom and "external" or "ajans:contract abc123" } },
        tabs = { { tab_id = "tab-1", workspace_id = "workspace-1", label = "main" } },
        panes = {
          {
            pane_id = "pane-1",
            terminal_id = "term-1",
            workspace_id = "workspace-1",
            tab_id = "tab-1",
            cwd = "/tmp/pane",
            agent = custom and nil or "contract",
          },
        },
        agents = custom and {} or {
          {
            name = "ajans:contract abc123",
            agent = "contract",
            terminal_id = "term-1",
            pane_id = "pane-1",
            workspace_id = "workspace-1",
            tab_id = "tab-1",
            cwd = "/tmp/contract",
          },
        },
      },
    })
  end
  Herdr._run_many = function(commands)
    assert.are.equal(1, #commands)
    assert.are.same({ "herdr", "pane", "process-info", "--pane", "pane-1" }, commands[1])
    return {
      success({
        type = "pane_process_info",
        process_info = {
          pane_id = "pane-1",
          shell_pid = 101,
          foreground_process_group_id = 102,
          foreground_processes = {
            { pid = 103, name = "contract-agent", argv = { "contract-agent", "--flag" }, cwd = "/tmp/contract" },
          },
        },
      }),
    }
  end
  return Herdr.sessions()
end

local capability_names = {
  "discovery",
  "stable_identity",
  "creation",
  "lifecycle",
  "input",
  "input_failure_safety",
  "display",
  "scrollback",
  "existing_sessions",
  "namespaces_errors",
}

local adapters = {
  tmux = {
    discovery = function()
      setup_config("tmux")
      local sessions = tmux_discovery()
      assert.are.equal(1, #sessions)
      assert.are.equal("contract", sessions[1].tool.name)
      assert.are.equal("/tmp/contract", sessions[1].cwd)
      assert.are.same({ 101, 102, 103 }, sessions[1].pids)
    end,
    stable_identity = function()
      setup_config("tmux")
      local first = tmux_discovery()[1]
      local second = tmux_discovery()[1]
      assert.are.equal("tmux 101", first.id)
      assert.are.equal(first.id, second.id)
      assert.are.equal(first.tmux_pane_id, second.tmux_pane_id)
    end,
    creation = function()
      setup_config("tmux", { create = "terminal" })
      local embedded = tmux_session({ env = { SET = "value", UNSET = false } })
      embedded.external = false
      local attach = embedded:start()
      assert.are.equal("tmux", attach.cmd[1])
      assert.is_true(vim.tbl_contains(attach.cmd, "contract-agent"))
      assert.is_true(vim.tbl_contains(attach.cmd, "SET=value"))
      assert.is_true(vim.tbl_contains(attach.cmd, "UNSET"))

      local spawned = {}
      Tmux.spawn = function(self, cmd)
        spawned[#spawned + 1] = vim.deepcopy(cmd)
        self.started = true
      end
      setup_config("tmux", { create = "window" })
      tmux_session({ external = true }):start()
      assert.are.equal("new-window", spawned[1][2])
      setup_config("tmux", { create = "split", split = { vertical = false, size = 20 } })
      tmux_session({ external = true }):start()
      assert.are.equal("split-window", spawned[2][2])
      assert.is_true(vim.tbl_contains(spawned[2], "-v"))
      assert.is_true(vim.tbl_contains(spawned[2], "20"))
    end,
    lifecycle = function()
      setup_config("tmux")
      local embedded = tmux_session({ started = true })
      assert.are.same({ "tmux", "attach-session", "-t", embedded.sid }, embedded:attach().cmd)
      assert.is_nil(tmux_session({ started = true, external = true }):attach())
      local calls = 0
      Util.exec = function()
        calls = calls + 1
      end
      embedded:detach()
      assert.are.equal(0, calls)
      vim.api.nvim_get_proc = function(pid)
        return pid == 101 and { pid = pid, ppid = 1 } or nil
      end
      assert.is_true(embedded:is_running())
    end,
    input = function()
      setup_config("tmux")
      local calls = {}
      local deferred
      local session = tmux_session({ mux_focus = true })
      Util.exec = function(cmd, opts)
        calls[#calls + 1] = { cmd = vim.deepcopy(cmd), opts = vim.deepcopy(opts or {}) }
        return {}
      end
      vim.defer_fn = function(callback, delay)
        assert.are.equal(50, delay)
        deferred = callback
        return 1
      end
      session:send("line one\nline two")
      session:submit()
      assert.are.same({ "tmux", "send-keys", "-t", "%1", "Escape", "[", "I" }, calls[1].cmd)
      deferred()
      assert.are.equal("line one\nline two", calls[2].opts.stdin)
      assert.are.same({ "tmux", "send-keys", "-t", "%1", "Enter" }, calls[4].cmd)
    end,
    input_failure_safety = function()
      setup_config("tmux")
      vim.defer_fn = function(callback)
        callback()
        return 1
      end

      for _, failure in ipairs({ "focus", "load-buffer", "paste-buffer" }) do
        local calls = {}
        local session = tmux_session({ mux_focus = failure == "focus" })
        Util.exec = function(cmd)
          calls[#calls + 1] = vim.deepcopy(cmd)
          local stage = cmd[2]
          if stage == "send-keys" and cmd[#cmd] == "I" then
            stage = "focus"
          end
          if stage == failure then
            return nil
          end
          return {}
        end

        session:send("repository context")
        session:submit()

        assert.is_false(vim.tbl_contains(
          vim.tbl_map(function(cmd)
            return cmd[#cmd]
          end, calls),
          "Enter"
        ))
        calls = {}
        Util.exec = function(cmd)
          calls[#calls + 1] = vim.deepcopy(cmd)
          return {}
        end
        session:send("fresh context")
        session:submit()
        assert.are.equal("Enter", calls[#calls][#calls[#calls]])
      end

      local calls = {}
      local unresolved = tmux_session({ external = true })
      unresolved.tmux_pane_id = nil
      Util.exec = function(cmd)
        calls[#calls + 1] = cmd
        return {}
      end
      unresolved:send("repository context")
      assert.are.same({}, calls)
      assert.is_false(unresolved._last_send_ok)

      local process = "contract-agent"
      local current = "zsh"
      local protected = tmux_session()
      protected.tool.is_proc = function(_, proc)
        return proc.cmd == "contract-agent"
      end
      Procs.new = function()
        return {
          walk = function(_, _, callback)
            local proc = { pid = 101, cmd = process }
            assert.is_string(proc.cmd)
            callback(proc)
          end,
        }
      end
      Util.exec = function(cmd)
        assert.are.equal("display-message", cmd[2])
        return { "101:" .. current }
      end
      assert.is_false(protected:accepts_automated_input())
      current = "contract-agent"
      assert.is_true(protected:accepts_automated_input())

      local deferred_send
      local delivered = false
      protected.tool.mux_focus = true
      vim.defer_fn = function(callback)
        deferred_send = callback
        return 1
      end
      Util.exec = function(cmd)
        if cmd[2] == "display-message" then
          return { "101:" .. current }
        end
        if cmd[2] == "load-buffer" or cmd[2] == "paste-buffer" then
          delivered = true
        end
        return {}
      end
      protected:send("secret")
      current = "zsh"
      deferred_send()
      assert.is_false(delivered)
      assert.is_false(protected._last_send_ok)
    end,
    display = function()
      setup_config("tmux", { create = "split" })
      vim.env.TMUX = "host"
      local fresh = tmux_session()
      fresh.started = nil
      fresh.external = nil
      fresh:init()
      assert.is_true(fresh.external)
      assert.are.equal(10, fresh.priority)
      local embedded = tmux_session({ started = true })
      embedded:init()
      assert.is_false(embedded.external)
      assert.are.equal(50, embedded.priority)
    end,
    scrollback = function()
      setup_config("tmux", { dump = 25 })
      Util.exec = function(cmd)
        assert.are.same({ "tmux", "capture-pane", "-p", "-t", "%1", "-S", "-25", "-E", "-", "-e" }, cmd)
        return { "red" }, "\27[31mred\27[0m\n"
      end
      assert.are.equal("\27[31mred\27[0m\n", tmux_session():dump())
      assert.is_true(Scrollback.is_enabled({ parent = { dump = function() end }, tool = {} }))
      assert.is_false(Scrollback.is_enabled({ parent = { dump = function() end }, tool = { native_scroll = true } }))
    end,
    existing_sessions = function()
      setup_config("tmux")
      local session = tmux_discovery()[1]
      assert.are.equal("contract", session.tool.name)
      assert.are.equal("%1", session.tmux_pane_id)
      assert.are.same({ 101, 102, 103 }, session.pids)
    end,
    namespaces_errors = function()
      setup_config("tmux")
      Util.exec = function()
        return nil
      end
      local sessions, authoritative = Tmux.sessions()
      assert.are.same({}, sessions)
      assert.is_false(authoritative)
    end,
  },
  herdr = {
    discovery = function()
      setup_config("herdr")
      local sessions = herdr_discovery(false)
      assert.are.equal(1, #sessions)
      assert.are.equal("contract", sessions[1].tool.name)
      assert.are.equal("/tmp/contract", sessions[1].cwd)
      assert.are.same({}, sessions[1].pids)
    end,
    stable_identity = function()
      setup_config("herdr")
      local first = herdr_discovery(false)[1]
      local second = herdr_discovery(false)[1]
      assert.are.equal("herdr:term-1", first.identity)
      assert.are.equal(first.identity, second.identity)
      assert.are.equal(first.herdr_pane_id, second.herdr_pane_id)
      assert.are.equal(first.herdr_workspace_id, second.herdr_workspace_id)
      assert.are.equal(first.herdr_tab_id, second.herdr_tab_id)
    end,
    creation = function()
      Herdr.ensure_server = function()
        return true
      end
      local function find_call(calls, prefix)
        for _, cmd in ipairs(calls) do
          local matches = true
          for index, value in ipairs(prefix) do
            if cmd[index] ~= value then
              matches = false
              break
            end
          end
          if matches then
            return cmd
          end
        end
      end

      setup_config("herdr", { create = "terminal" })
      vim.env.HERDR_ENV = nil
      local workspace_calls = {}
      local embedded = herdr_session({ env = { SET = "value", UNSET = false } })
      embedded.started = nil
      embedded.external = nil
      embedded:init()
      Herdr._run = function(cmd)
        workspace_calls[#workspace_calls + 1] = vim.deepcopy(cmd)
        if cmd[2] == "workspace" and cmd[3] == "create" then
          return success({
            type = "workspace_created",
            workspace = { workspace_id = "workspace-new" },
            tab = { tab_id = "tab-new" },
            root_pane = { pane_id = "root-new" },
          })
        elseif cmd[2] == "agent" and cmd[3] == "start" then
          return success({
            type = "agent_started",
            agent = {
              terminal_id = "term-new",
              pane_id = "pane-new",
              workspace_id = "workspace-new",
              tab_id = "tab-new",
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "process-info" then
          return success({ type = "pane_process_info", process_info = {} })
        elseif cmd[2] == "pane" and cmd[3] == "close" then
          return completed()
        end
        error("unexpected workspace command")
      end
      local attach = embedded:start()
      assert.are.same({ "herdr", "agent", "attach", "term-new" }, attach.cmd)
      assert.are.equal("workspace", embedded.herdr_placement)
      local workspace_start = assert(find_call(workspace_calls, { "herdr", "agent", "start" }))
      assert.is_true(vim.tbl_contains(workspace_start, "SET=value"))
      assert.is_true(vim.tbl_contains(workspace_start, "UNSET"))
      assert.is_true(vim.tbl_contains(workspace_start, "contract-agent"))
      assert.is_not_nil(find_call(workspace_calls, { "herdr", "pane", "close", "root-new" }))

      vim.env.HERDR_ENV = "1"
      vim.env.HERDR_WORKSPACE_ID = "workspace-host"
      vim.env.HERDR_TAB_ID = "tab-host"
      setup_config("herdr", { create = "window" })
      local tab_calls = {}
      local tab = herdr_session({ external = true })
      tab.started = nil
      Herdr._run = function(cmd)
        tab_calls[#tab_calls + 1] = vim.deepcopy(cmd)
        if cmd[2] == "tab" and cmd[3] == "create" then
          return success({
            type = "tab_created",
            tab = { tab_id = "tab-window" },
            root_pane = { pane_id = "root-window" },
          })
        elseif cmd[2] == "agent" and cmd[3] == "start" then
          return success({
            type = "agent_started",
            agent = {
              terminal_id = "term-window",
              pane_id = "pane-window",
              workspace_id = "workspace-host",
              tab_id = "tab-window",
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "process-info" then
          return success({ type = "pane_process_info", process_info = {} })
        elseif cmd[2] == "pane" and cmd[3] == "close" then
          return completed()
        end
        error("unexpected tab command")
      end
      tab:start()
      assert.is_true(tab.started)
      assert.are.equal("tab", tab.herdr_placement)
      assert.is_not_nil(find_call(tab_calls, { "herdr", "tab", "create" }))
      assert.is_not_nil(find_call(tab_calls, { "herdr", "pane", "close", "root-window" }))

      setup_config("herdr", { create = "split", split = { vertical = true, size = 0.8 } })
      local split_calls = {}
      local split = herdr_session({ external = true })
      split.started = nil
      Herdr._run = function(cmd)
        split_calls[#split_calls + 1] = vim.deepcopy(cmd)
        if cmd[2] == "agent" and cmd[3] == "start" then
          return success({
            type = "agent_started",
            agent = {
              terminal_id = "term-split",
              pane_id = "pane-split",
              workspace_id = "workspace-host",
              tab_id = "tab-host",
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "layout" then
          return success({
            type = "pane_layout",
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
        elseif cmd[2] == "pane" and cmd[3] == "resize" then
          return success({
            type = "pane_resize",
            resize = {
              changed = true,
              layout = {
                panes = { { pane_id = "pane-split", rect = { x = 20, y = 0, width = 80, height = 40 } } },
                splits = {
                  {
                    id = "immediate",
                    direction = "right",
                    ratio = 0.2,
                    rect = { x = 0, y = 0, width = 100, height = 40 },
                  },
                },
              },
            },
          })
        elseif cmd[2] == "pane" and cmd[3] == "process-info" then
          return success({ type = "pane_process_info", process_info = {} })
        end
        error("unexpected split command")
      end
      split:start()
      assert.is_true(split.started)
      assert.are.equal("split", split.herdr_placement)
      local split_start = assert(find_call(split_calls, { "herdr", "agent", "start" }))
      assert.is_true(vim.tbl_contains(split_start, "right"))
      assert.is_not_nil(find_call(split_calls, { "herdr", "pane", "resize" }))
    end,
    lifecycle = function()
      setup_config("herdr")
      local embedded = herdr_session({ started = true })
      assert.are.same({ "herdr", "agent", "attach", "term-1" }, embedded:attach().cmd)
      assert.is_nil(herdr_session({ started = true, external = true }):attach())
      local calls = 0
      Herdr._run = function(cmd)
        calls = calls + 1
        assert.are.same({ "herdr", "agent", "get", "term-1" }, cmd)
        return success({ type = "agent_info", agent = { terminal_id = "term-1" } })
      end
      assert.is_true(embedded:is_running())
      embedded:detach()
      assert.are.equal(1, calls)
      local reopened = herdr_session({ started = true })
      assert.are.same(embedded:attach(), reopened:attach())
    end,
    input = function()
      setup_config("herdr")
      local calls = {}
      local session = herdr_session({ mux_focus = true })
      Herdr._run = function(cmd)
        calls[#calls + 1] = vim.deepcopy(cmd)
        return cmd[3] == "send" and success({ type = "ok" }) or completed()
      end
      assert.is_true(session:send("line one\nline two"))
      assert.is_true(session:submit())
      assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "escape", "[", "I" }, calls[1])
      assert.are.same({ "herdr", "agent", "send", "term-1", "line one\nline two" }, calls[2])
      assert.are.same({ "herdr", "pane", "send-keys", "pane-1", "enter" }, calls[3])
    end,
    input_failure_safety = function()
      setup_config("herdr")
      local calls = {}
      local session = herdr_session()
      Herdr._run = function(cmd)
        calls[#calls + 1] = vim.deepcopy(cmd)
        return cmd[3] == "send" and completed("", 1, "agent disappeared") or completed()
      end

      assert.is_false(session:send("repository context"))
      assert.is_false(session:submit())
      assert.are.equal(1, #calls)
    end,
    display = function()
      setup_config("herdr")
      vim.env.HERDR_ENV = "1"
      local external = herdr_session({ started = true, external = true })
      external:init()
      assert.is_true(external.external)
      assert.are.equal(10, external.priority)
      local embedded = herdr_session({ started = true })
      embedded:init()
      assert.is_false(embedded.external)
      assert.are.equal(50, embedded.priority)
      assert.are.equal("herdr:term-1", embedded.identity)
    end,
    scrollback = function()
      setup_config("herdr", { dump = 25 })
      Herdr._run = function(cmd)
        assert.are.same({ "herdr", "pane", "read", "pane-1", "--source", "recent", "--lines", "25", "--ansi" }, cmd)
        return completed("\27[31mred\27[0m\n")
      end
      assert.are.equal("\27[31mred\27[0m\n", herdr_session():dump())
      assert.is_true(Scrollback.is_enabled({ parent = { dump = function() end }, tool = {} }))
      assert.is_false(Scrollback.is_enabled({ parent = { dump = function() end }, tool = { native_scroll = true } }))
    end,
    existing_sessions = function()
      setup_config("herdr")
      local session = herdr_discovery(true)[1]
      assert.are.equal("contract", session.tool.name)
      assert.is_false(session.herdr_agent)
      assert.are.same({ "herdr", "terminal", "attach", "term-1" }, setmetatable(session, Herdr):attach().cmd)
    end,
    namespaces_errors = function()
      setup_config("herdr")
      vim.env.HERDR_SESSION = "contract-team"
      vim.env.HERDR_SOCKET_PATH = "/tmp/contract.sock"
      Herdr.supports_snapshot = function()
        return true
      end
      local seen_opts
      Herdr._run = function(cmd, opts)
        seen_opts = opts
        assert.are.same({ "herdr", "api", "snapshot" }, cmd)
        return completed("", 1, "failed to connect to Herdr server: Connection refused\n")
      end
      local sessions, authoritative = Herdr.sessions()
      assert.are.same({}, sessions)
      assert.is_true(authoritative)
      assert.is_nil(seen_opts.env)
    end,
  },
}

describe("multiplexer parity contract", function()
  local originals

  before_each(function()
    originals = {
      exec = Util.exec,
      error = Util.error,
      info = Util.info,
      herdr_run = Herdr._run,
      herdr_trusted_socket = Client.trusted_socket,
      herdr_run_many = Herdr._run_many,
      herdr_supports_snapshot = Herdr.supports_snapshot,
      herdr_ensure_server = Herdr.ensure_server,
      tmux_panes = Tmux.panes,
      tmux_clients = Tmux.clients,
      tmux_spawn = Tmux.spawn,
      procs_new = Procs.new,
      procs_pids = Procs.pids,
      defer_fn = vim.defer_fn,
      nvim_get_proc = vim.api.nvim_get_proc,
      tmux_env = vim.env.TMUX,
      herdr_env = vim.env.HERDR_ENV,
      workspace_id = vim.env.HERDR_WORKSPACE_ID,
      tab_id = vim.env.HERDR_TAB_ID,
      herdr_session = vim.env.HERDR_SESSION,
      socket_path = vim.env.HERDR_SOCKET_PATH,
    }
    Util.error = function() end
    Util.info = function() end
    Client.trusted_socket = function()
      return "/tmp/herdr-test.sock"
    end
  end)

  after_each(function()
    Util.exec = originals.exec
    Util.error = originals.error
    Util.info = originals.info
    Herdr._run = originals.herdr_run
    Client.trusted_socket = originals.herdr_trusted_socket
    Herdr._run_many = originals.herdr_run_many
    Herdr.supports_snapshot = originals.herdr_supports_snapshot
    Herdr.ensure_server = originals.herdr_ensure_server
    Tmux.panes = originals.tmux_panes
    Tmux.clients = originals.tmux_clients
    Tmux.spawn = originals.tmux_spawn
    Procs.new = originals.procs_new
    Procs.pids = originals.procs_pids
    vim.defer_fn = originals.defer_fn
    vim.api.nvim_get_proc = originals.nvim_get_proc
    vim.env.TMUX = originals.tmux_env
    vim.env.HERDR_ENV = originals.herdr_env
    vim.env.HERDR_WORKSPACE_ID = originals.workspace_id
    vim.env.HERDR_TAB_ID = originals.tab_id
    vim.env.HERDR_SESSION = originals.herdr_session
    vim.env.HERDR_SOCKET_PATH = originals.socket_path
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("contains every required capability with no skip or unsupported hooks", function()
    assert.are.same({ "herdr", "tmux" }, vim.fn.sort(vim.tbl_keys(adapters)))
    for adapter_name, adapter in pairs(adapters) do
      assert.are.equal(#capability_names, vim.tbl_count(adapter))
      for _, capability in ipairs(capability_names) do
        assert.are.equal("function", type(adapter[capability]), adapter_name .. " missing " .. capability)
      end
      assert.is_nil(adapter.skip)
      assert.is_nil(adapter.unsupported)
    end
  end)

  for _, capability in ipairs(capability_names) do
    for _, adapter_name in ipairs({ "tmux", "herdr" }) do
      it(adapter_name .. " satisfies " .. capability, function()
        adapters[adapter_name][capability]()
      end)
    end
  end
end)
