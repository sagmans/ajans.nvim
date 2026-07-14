---@module 'luassert'

local Client = require("ajans.cli.session.herdr.client")

describe("Herdr client", function()
  local original_status
  local original_exchange
  local original_spawn
  local original_new_pipe
  local original_wait
  local original_system
  local original_environ
  local original_validate_socket
  local original_fs_stat
  local original_fs_lstat
  local original_getuid

  before_each(function()
    original_status = Client._status
    original_exchange = Client._exchange
    original_spawn = vim.uv.spawn
    original_new_pipe = vim.uv.new_pipe
    original_wait = vim.wait
    original_system = vim.system
    original_environ = vim.fn.environ
    original_validate_socket = Client.validate_socket
    original_fs_stat = Client._fs_stat
    original_fs_lstat = Client._fs_lstat
    original_getuid = Client._getuid
    Client._request_id = 0
  end)

  after_each(function()
    Client._status = original_status
    Client._exchange = original_exchange
    vim.uv.spawn = original_spawn
    vim.uv.new_pipe = original_new_pipe
    vim.wait = original_wait
    vim.system = original_system
    vim.fn.environ = original_environ
    Client.validate_socket = original_validate_socket
    Client._fs_stat = original_fs_stat
    Client._fs_lstat = original_fs_lstat
    Client._getuid = original_getuid
  end)

  local function capture_request(response)
    local captured
    Client._status = function()
      return { running = true, socket = "/tmp/herdr-test.sock" }
    end
    Client.validate_socket = function()
      return true
    end
    Client._exchange = function(path, payload, timeout)
      captured = { path = path, payload = vim.json.decode(payload), timeout = timeout }
      local value = vim.deepcopy(response or { result = { ok = true } })
      value.id = value.id or captured.payload.id
      return vim.json.encode(value)
    end
    return function()
      return captured
    end
  end

  it("frames fragmented socket responses and closes the pipe", function()
    local observed = {}
    local pipe = {
      connect = function(_, path, callback)
        observed.path = path
        callback()
      end,
      read_start = function(_, callback)
        callback(nil, '{"result":')
        callback(nil, '{"ok":true}}\nignored')
      end,
      write = function(_, payload, callback)
        observed.payload = payload
        callback()
      end,
      read_stop = function()
        observed.stopped = true
      end,
      is_closing = function()
        return false
      end,
      close = function()
        observed.closed = true
      end,
    }
    vim.uv.new_pipe = function()
      return pipe
    end

    local response = Client._exchange("/tmp/herdr.sock", '{"id":"test"}', 100)

    assert.are.equal('{"result":{"ok":true}}', response)
    assert.are.equal("/tmp/herdr.sock", observed.path)
    assert.are.equal('{"id":"test"}\n', observed.payload)
    assert.is_true(observed.stopped)
    assert.is_true(observed.closed)
  end)

  it("rejects oversized socket responses", function()
    local closed = false
    vim.uv.new_pipe = function()
      return {
        connect = function(_, _, callback)
          callback()
        end,
        read_start = function(_, callback)
          callback(nil, string.rep("x", Client.MAX_RESPONSE_BYTES + 1))
        end,
        write = function(_, _, callback)
          callback()
        end,
        is_closing = function()
          return false
        end,
        read_stop = function() end,
        close = function()
          closed = true
        end,
      }
    end

    local response, err = Client._exchange("/tmp/herdr.sock", "{}", 100)

    assert.is_nil(response)
    assert.matches("size limit", err)
    assert.is_true(closed)
  end)

  it("closes a socket request when its deadline expires", function()
    local closed = false
    vim.uv.new_pipe = function()
      return {
        connect = function() end,
        is_closing = function()
          return false
        end,
        read_stop = function() end,
        close = function()
          closed = true
        end,
      }
    end
    vim.wait = function()
      return false
    end

    local response, err = Client._exchange("/tmp/herdr.sock", "{}", 100)

    assert.is_nil(response)
    assert.matches("timed out", err)
    assert.is_true(closed)
  end)

  it("resolves the production API socket from Herdr status", function()
    Client._status = original_status
    vim.system = function(cmd, opts)
      assert.are.same({ "herdr", "status", "server", "--json" }, cmd)
      assert.is_true(opts.text)
      return {
        wait = function(_, timeout)
          assert.are.equal(Client.TIMEOUT, timeout)
          return {
            code = 0,
            stdout = '{"running":true,"socket":"/tmp/herdr.sock"}\n',
            stderr = "",
          }
        end,
      }
    end

    local status = Client._status()

    assert.are.same({ running = true, socket = "/tmp/herdr.sock" }, status)
  end)

  for _, case in ipairs({
    { name = "non-socket path", stat = { type = "file", uid = 501, mode = 384 } },
    { name = "foreign owner", stat = { type = "socket", uid = 502, mode = 384 } },
    { name = "broad permissions", stat = { type = "socket", uid = 501, mode = 438 } },
    { name = "replaceable parent", stat = { type = "socket", uid = 501, mode = 384 }, parent_mode = 511 },
    { name = "foreign parent", stat = { type = "socket", uid = 501, mode = 384 }, parent_uid = 502 },
    { name = "symlink socket", stat = { type = "socket", uid = 501, mode = 384 }, socket_link = true },
  }) do
    it("rejects a " .. case.name, function()
      Client._fs_stat = function(path)
        if path == "/tmp/herdr.sock" then
          return case.stat
        end
        return { type = "directory", uid = case.parent_uid or 501, mode = case.parent_mode or 493 }
      end
      Client._fs_lstat = function(path)
        local value = vim.deepcopy(Client._fs_stat(path))
        if case.socket_link and path == "/tmp/herdr.sock" then
          value.type = "link"
        end
        return value
      end
      Client._getuid = function()
        return 501
      end

      local ok, err = Client.validate_socket("/tmp/herdr.sock")

      assert.is_false(ok)
      assert.is_string(err)
    end)
  end

  it("accepts an owner-only socket", function()
    Client._fs_stat = function(path)
      if path == "/tmp/herdr.sock" then
        return { type = "socket", uid = 501, mode = 384 }
      end
      return { type = "directory", uid = 501, mode = 493 }
    end
    Client._fs_lstat = Client._fs_stat
    Client._getuid = function()
      return 501
    end

    assert.is_true(Client.validate_socket("/tmp/herdr.sock"))
  end)

  it("sends prompt text through the local JSON socket", function()
    local captured = capture_request()

    local result = Client.run({ "herdr", "agent", "send", "term-1", "secret prompt" })

    assert.are.equal(0, result.code)
    assert.are.same({ target = "term-1", text = "secret prompt" }, captured().payload.params)
    assert.are.equal("agent.send", captured().payload.method)
    assert.are.equal("/tmp/herdr-test.sock", captured().path)
  end)

  it("sends custom-pane text through the local JSON socket", function()
    local captured = capture_request()

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "secret context" })

    assert.are.equal(0, result.code)
    assert.are.equal("pane.send_text", captured().payload.method)
    assert.are.same({ pane_id = "pane-1", text = "secret context" }, captured().payload.params)
  end)

  it("sends launch argv and environment through the local JSON socket", function()
    local captured = capture_request({ result = { agent = { terminal_id = "term-1" } } })

    local result = Client.run({
      "herdr",
      "agent",
      "start",
      "ajans:claude",
      "--cwd",
      "/tmp/project",
      "--workspace",
      "workspace-1",
      "--tab",
      "tab-1",
      "--split",
      "right",
      "--no-focus",
      "--env",
      "TOKEN=secret=value",
      "--",
      "env",
      "-u",
      "OLD_TOKEN",
      "--",
      "claude",
      "--api-key",
      "secret-arg",
    })

    assert.are.equal(0, result.code)
    assert.are.same({
      name = "ajans:claude",
      cwd = "/tmp/project",
      workspace_id = "workspace-1",
      tab_id = "tab-1",
      split = "right",
      focus = false,
      env = { TOKEN = "secret=value" },
      argv = { "env", "-u", "OLD_TOKEN", "--", "claude", "--api-key", "secret-arg" },
    }, captured().payload.params)
  end)

  it("rejects a missing Herdr API socket", function()
    Client._status = function()
      return { running = true }
    end

    local result = Client.run({ "herdr", "agent", "send", "term-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("missing a running API socket", result.stderr)
  end)

  it("rejects mismatched response IDs", function()
    capture_request({ id = "another-client", result = { ok = true } })

    local result = Client.run({ "herdr", "agent", "send", "term-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("mismatched response ID", result.stderr)
  end)

  it("rejects an incompatible server before writing secrets", function()
    local exchanged = false
    Client._status = function()
      return { running = true, compatible = false, socket = "/tmp/herdr-test.sock" }
    end
    Client._exchange = function()
      exchanged = true
    end

    local result = Client.run({ "herdr", "agent", "send", "term-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.is_false(exchanged)
  end)

  it("propagates Herdr API error envelopes", function()
    local captured = capture_request({ error = { code = "pane_not_found", message = "gone" } })

    local result = Client.run({ "herdr", "agent", "send", "term-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("pane_not_found", result.stderr)
    assert.are.equal("agent.send", captured().payload.method)
  end)

  it("keeps project secrets out of the detached server environment", function()
    vim.fn.environ = function()
      return {
        HOME = "/home/test",
        PATH = "/usr/bin",
        HERDR_SOCKET_PATH = "/tmp/herdr.sock",
        PROJECT_SECRET = "must-not-persist",
      }
    end
    local observed
    local handle = { unref = function() end }
    vim.uv.spawn = function(_, opts)
      observed = opts
      return handle, 42
    end

    assert.is_true(Client.spawn_server())
    assert.are.same({
      "HOME=/home/test",
      "PATH=/usr/bin",
      "HERDR_SOCKET_PATH=/tmp/herdr.sock",
    }, observed.env)
  end)

  it("reports detached server spawn failures", function()
    vim.uv.spawn = function()
      return nil, "EACCES"
    end

    local ok, err = Client.spawn_server()

    assert.is_false(ok)
    assert.matches("EACCES", err)
  end)

  it("removes project secrets from the persistent server environment", function()
    vim.fn.environ = function()
      return {
        HOME = "/tmp/home",
        PATH = "/usr/bin",
        HERDR_CONFIG_PATH = "/tmp/herdr.toml",
        HERDR_SESSION = "project",
        HERDR_SOCKET_PATH = "/tmp/herdr.sock",
        PROJECT_SECRET = "must-not-persist",
      }
    end

    assert.are.same({
      "HOME=/tmp/home",
      "PATH=/usr/bin",
      "HERDR_CONFIG_PATH=/tmp/herdr.toml",
      "HERDR_SESSION=project",
      "HERDR_SOCKET_PATH=/tmp/herdr.sock",
    }, Client.server_env())
  end)

  it("spawns and unreferences the detached Herdr server", function()
    local observed
    local handle = {
      unref = function(self)
        self.unreferenced = true
      end,
      is_closing = function()
        return false
      end,
      close = function(self)
        self.closed = true
      end,
    }
    vim.uv.spawn = function(command, opts, callback)
      observed = { command = command, opts = opts, callback = callback }
      return handle, 42
    end

    local ok = Client.spawn_server()

    assert.is_true(ok)
    assert.are.equal("herdr", observed.command)
    assert.are.same({ "server" }, observed.opts.args)
    assert.is_true(observed.opts.detached)
    assert.are.same(Client.server_env(), observed.opts.env)
    assert.is_true(handle.unreferenced)
    observed.callback()
    assert.is_true(handle.closed)
  end)
end)
