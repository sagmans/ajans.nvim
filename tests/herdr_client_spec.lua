local Test = require("tests.helpers.test")
local assert, describe, it = Test.assert, Test.describe, Test.it
local before_each, after_each = Test.before_each, Test.after_each

local Client = require("ajans.cli.session.herdr.client")

---@class tests.herdr_client.FsApi
---@field _fs_stat fun(path:string):uv.fs_stat.result?
---@field _fs_lstat fun(path:string):uv.fs_stat.result?
---@field _fs_realpath fun(path:string):string?
local Fs = Client --[[@as tests.herdr_client.FsApi]]

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
  local original_fs_realpath

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
    original_fs_realpath = Client._fs_realpath
    Fs._fs_realpath = function(path)
      return path
    end
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
    Client._fs_realpath = original_fs_realpath
  end)

  local function capture_request(response)
    local captured
    Client._status = function()
      return { running = true, socket = "/tmp/herdr-test.sock" }
    end
    Client.validate_socket = function(path)
      return true, nil, path
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
        local stat = Client._fs_stat(path)
        if not stat then
          error("expected a filesystem fixture", 2)
        end
        local value = vim.deepcopy(stat)
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

  it("accepts an owner-only socket through macOS directory aliases", function()
    Fs._fs_realpath = function(path)
      assert.are.equal("/tmp", path)
      return "/private/tmp"
    end
    Fs._fs_stat = function(path)
      if path == "/tmp/herdr.sock" or path == "/private/tmp/herdr.sock" then
        return { type = "socket", uid = 501, mode = 384 }
      end
      return { type = "directory", uid = path == "/private" and 0 or 501, mode = path == "/private/tmp" and 1023 or 493 }
    end
    Fs._fs_lstat = function(path)
      if path == "/tmp/herdr.sock" then
        return { type = "socket", uid = 501, mode = 384 }
      elseif path == "/tmp" then
        return { type = "link", uid = 0, mode = 511 }
      end
      return Fs._fs_stat(path)
    end
    Client._getuid = function()
      return 501
    end

    local safe, _, resolved = Client.validate_socket("/tmp/herdr.sock")
    assert.is_true(safe)
    assert.are.equal("/private/tmp/herdr.sock", resolved)
  end)

  it("connects only through the validated canonical socket path", function()
    Client._status = function()
      return { running = true, compatible = true, socket = "/tmp/herdr.sock" }
    end
    Client.validate_socket = function(path)
      assert.are.equal("/tmp/herdr.sock", path)
      return true, nil, "/private/tmp/herdr.sock"
    end
    local connected
    Client._exchange = function(path, payload)
      connected = path
      local request = vim.json.decode(payload)
      return vim.json.encode({ id = request.id, result = { ok = true } })
    end

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "secret" })

    assert.are.equal(0, result.code)
    assert.are.equal("/private/tmp/herdr.sock", connected)
  end)

  it("accepts an owner-only socket", function()
    Client._fs_stat = function(path)
      if path == "/tmp/herdr.sock" then
        return { type = "socket", uid = 501, mode = 384 }
      end
      return { type = "directory", uid = 501, mode = 493 }
    end
    Fs._fs_lstat = Fs._fs_stat
    Client._getuid = function()
      return 501
    end

    assert.is_true(Client.validate_socket("/tmp/herdr.sock"))
  end)

  it("creates a workspace without exposing its environment to a subprocess", function()
    local captured = capture_request()

    local result = Client.run({
      "herdr",
      "workspace",
      "create",
      "--cwd",
      "/tmp/project",
      "--label",
      "ajans:pi abc123",
      "--no-focus",
      "--env",
      "TOKEN=secret=value",
    })

    assert.are.equal(0, result.code)
    assert.are.same({
      cwd = "/tmp/project",
      label = "ajans:pi abc123",
      focus = false,
      env = { TOKEN = "secret=value" },
    }, captured().payload.params)
    assert.are.equal("workspace.create", captured().payload.method)
    assert.are.equal("/tmp/herdr-test.sock", captured().path)
  end)

  it("creates a tab without exposing its environment to a subprocess", function()
    local captured = capture_request()

    local result = Client.run({
      "herdr",
      "tab",
      "create",
      "--workspace",
      "w1",
      "--cwd",
      "/tmp/project",
      "--label",
      "ajans:pi abc123",
      "--no-focus",
      "--env",
      "TOKEN=secret",
    })

    assert.are.equal(0, result.code)
    assert.are.same({
      workspace_id = "w1",
      cwd = "/tmp/project",
      label = "ajans:pi abc123",
      focus = false,
      env = { TOKEN = "secret" },
    }, captured().payload.params)
    assert.are.equal("tab.create", captured().payload.method)
  end)

  it("splits a pane without exposing its environment to a subprocess", function()
    local captured = capture_request()

    local result = Client.run({
      "herdr",
      "pane",
      "split",
      "--pane",
      "w1:p1",
      "--direction",
      "right",
      "--cwd",
      "/tmp/project",
      "--no-focus",
      "--env",
      "TOKEN=secret",
    })

    assert.are.equal(0, result.code)
    assert.are.same({
      target_pane_id = "w1:p1",
      direction = "right",
      cwd = "/tmp/project",
      focus = false,
      env = { TOKEN = "secret" },
    }, captured().payload.params)
    assert.are.equal("pane.split", captured().payload.method)
  end)

  it("sends custom-pane text through the local JSON socket", function()
    local captured = capture_request()

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "secret context" })

    assert.are.equal(0, result.code)
    assert.are.equal("pane.send_text", captured().payload.method)
    assert.are.same({ pane_id = "pane-1", text = "secret context" }, captured().payload.params)
  end)

  it("starts a Herdr 0.8 agent through the local JSON socket", function()
    local captured = capture_request({ result = { agent = { terminal_id = "term-1" } } })

    local result = Client.run({
      "herdr",
      "agent",
      "start",
      "ajans-pi-0123456789ab",
      "--kind",
      "pi",
      "--pane",
      "w1:p2",
      "--timeout",
      "30000",
      "--",
      "--model",
      "secret-arg",
    })

    assert.are.equal(0, result.code)
    assert.are.same({
      name = "ajans-pi-0123456789ab",
      kind = "pi",
      pane_id = "w1:p2",
      timeout_ms = 30000,
      args = { "--model", "secret-arg" },
    }, captured().payload.params)
    assert.are.equal(30000 + Client.REQUEST_TIMEOUT_GRACE, captured().timeout)
  end)

  it("rejects a missing Herdr API socket", function()
    Client._status = function()
      return { running = true }
    end

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("missing a running API socket", result.stderr)
  end)

  it("rejects mismatched response IDs", function()
    capture_request({ id = "another-client", result = { ok = true } })

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("mismatched response ID", result.stderr)
  end)

  it("rejects an unsafe socket before writing secrets", function()
    local exchanged = false
    Client._status = function()
      return { running = true, socket = "/tmp/herdr-test.sock" }
    end
    Client.validate_socket = function()
      return false, "Herdr API socket is unsafe"
    end
    Client._exchange = function()
      exchanged = true
    end

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "secret" })

    assert.are.equal(1, result.code)
    assert.matches("unsafe", result.stderr)
    assert.is_false(exchanged)
  end)

  it("rejects an incompatible server before writing secrets", function()
    local exchanged = false
    Client._status = function()
      return { running = true, compatible = false, socket = "/tmp/herdr-test.sock" }
    end
    Client._exchange = function()
      exchanged = true
    end

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.is_false(exchanged)
  end)

  it("uses a compatible server that recommends restart", function()
    local captured = capture_request()
    Client._status = function()
      return {
        running = true,
        compatible = true,
        restart_needed = true,
        socket = "/tmp/herdr-test.sock",
      }
    end

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "prompt" })

    assert.are.equal(0, result.code)
    assert.are.equal("pane.send_text", captured().payload.method)
  end)

  it("propagates Herdr API error envelopes", function()
    local captured = capture_request({ error = { code = "pane_not_found", message = "gone" } })

    local result = Client.run({ "herdr", "pane", "send-text", "pane-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("pane_not_found", result.stderr)
    assert.are.equal("pane.send_text", captured().payload.method)
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
