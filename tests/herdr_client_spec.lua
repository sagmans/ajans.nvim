---@module 'luassert'

local Client = require("ajans.cli.session.herdr.client")

describe("Herdr client", function()
  local original_status
  local original_exchange
  local original_spawn
  local original_new_pipe
  local original_wait
  local original_system

  before_each(function()
    original_status = Client._status
    original_exchange = Client._exchange
    original_spawn = vim.uv.spawn
    original_new_pipe = vim.uv.new_pipe
    original_wait = vim.wait
    original_system = vim.system
    Client._request_id = 0
  end)

  after_each(function()
    Client._status = original_status
    Client._exchange = original_exchange
    vim.uv.spawn = original_spawn
    vim.uv.new_pipe = original_new_pipe
    vim.wait = original_wait
    vim.system = original_system
  end)

  local function capture_request(response)
    local captured
    Client._status = function()
      return { running = true, socket = "/tmp/herdr-test.sock" }
    end
    Client._exchange = function(path, payload, timeout)
      captured = { path = path, payload = vim.json.decode(payload), timeout = timeout }
      return vim.json.encode(response or { result = { ok = true } })
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

  it("propagates Herdr API error envelopes", function()
    local captured = capture_request({ error = { code = "pane_not_found", message = "gone" } })

    local result = Client.run({ "herdr", "agent", "send", "term-1", "prompt" })

    assert.are.equal(1, result.code)
    assert.matches("pane_not_found", result.stderr)
    assert.are.equal("agent.send", captured().payload.method)
  end)

  it("reports detached server spawn failures", function()
    vim.uv.spawn = function()
      return nil, "EACCES"
    end

    local ok, err = Client.spawn_server()

    assert.is_false(ok)
    assert.matches("EACCES", err)
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
    assert.is_true(handle.unreferenced)
    observed.callback()
    assert.is_true(handle.closed)
  end)
end)
