---@module 'luassert'

local Config = require("ajans.config")
local Discovery = require("ajans.cli.session.herdr.discovery")

local function success(result)
  return { code = 0, signal = 0, stdout = vim.json.encode({ id = "test", result = result }) .. "\n", stderr = "" }
end

describe("Herdr discovery", function()
  before_each(function()
    pcall(vim.api.nvim_del_user_command, "Ajans")
    Config.setup({
      cli = {
        mux = { backend = "herdr" },
        tools = {
          custom = {
            cmd = { "custom-agent" },
            is_proc = function(_, proc)
              return proc.cmd == "custom-agent"
            end,
          },
        },
      },
    })
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("classifies stable labels before inspecting only unmatched panes", function()
    local process_commands
    local backend = {
      supports_snapshot = function()
        return true
      end,
      request = function(args)
        assert.are.same({ "api", "snapshot" }, args)
        return {
          snapshot = {
            workspaces = { { workspace_id = "w1", label = "ajans:claude hash" } },
            tabs = { { tab_id = "t1", workspace_id = "w1" } },
            panes = {
              { pane_id = "known", terminal_id = "term-known", workspace_id = "w1", tab_id = "t1" },
              { pane_id = "custom", terminal_id = "term-custom", workspace_id = "w1", tab_id = "t1" },
            },
            agents = {
              {
                pane_id = "known",
                terminal_id = "term-known",
                workspace_id = "w1",
                tab_id = "t1",
                name = "ajans:claude hash",
                process_info = { shell_pid = 10 },
              },
            },
          },
        }
      end,
      _run_many = function(commands)
        process_commands = commands
        return {
          success({
            process_info = {
              shell_pid = 20,
              foreground_processes = { { pid = 21, cmdline = "custom-agent", cwd = "/custom" } },
            },
          }),
        }
      end,
    }

    local sessions, complete = Discovery.sessions(backend)
    table.sort(sessions, function(left, right)
      return left.herdr_pane_id < right.herdr_pane_id
    end)

    assert.is_true(complete)
    assert.are.equal(2, #sessions)
    assert.are.same({ "herdr", "pane", "process-info", "--pane", "custom" }, process_commands[1])
    assert.are.same({ 20, 21 }, sessions[1].pids)
    assert.are.equal("/custom", sessions[1].cwd)
    assert.are.same({ 10 }, sessions[2].pids)
  end)

  for _, missing in ipairs({ "workspaces", "tabs", "panes", "agents" }) do
    it("rejects a snapshot missing " .. missing, function()
      local snapshot = { workspaces = {}, tabs = {}, panes = {}, agents = {} }
      snapshot[missing] = nil
      local backend = {
        supports_snapshot = function()
          return true
        end,
        request = function()
          return { snapshot = snapshot }
        end,
      }

      local sessions, complete = Discovery.sessions(backend)

      assert.are.same({}, sessions)
      assert.is_false(complete)
    end)
  end

  it("normalizes labels and process metadata", function()
    assert.are.equal("copilot", Discovery.tool_name_for_label(" GitHub Copilot "))
    assert.are.same(
      { 1, 2, 3 },
      Discovery.process_pids({
        shell_pid = 1,
        foreground_process_group_id = 2,
        foreground_processes = { { pid = 2 }, { pid = 3 } },
      })
    )
    local proc = Discovery.to_proc({
      pid = 7,
      argv0 = "custom-agent",
      argv = { "custom-agent", "--flag" },
      cwd = "/tmp",
    })
    assert.are.equal(7, proc.pid)
    assert.are.equal(0, proc.ppid)
    assert.are.equal("custom-agent --flag", proc.cmd)
    assert.are.equal("custom-agent", proc.executable)
    assert.are.equal("/tmp", proc.cwd)
  end)

  it("hydrates matcher metadata from one process inventory", function()
    local inventory = {
      get = function(_, pid)
        assert.are.equal(7, pid)
        return {
          pid = 7,
          ppid = 5,
          cmd = "/usr/bin/custom-agent --flag",
          executable = "/usr/bin/custom-agent",
          cwd = "/inventory",
          env = { TOKEN = "value" },
        }
      end,
    }

    local proc = Discovery.to_proc({ pid = 7, name = "custom-agent" }, inventory)

    assert.are.equal(5, proc.ppid)
    assert.are.equal("/usr/bin/custom-agent", proc.executable)
    assert.are.equal("/inventory", proc.cwd)
    assert.are.same({ TOKEN = "value" }, proc.env)
  end)
end)
