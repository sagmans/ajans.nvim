---@module 'luassert'

local Config = require("ajans.config")

local function setup_config(opts)
  pcall(vim.api.nvim_del_user_command, "Ajans")
  Config.setup(opts)
end

describe("config", function()
  after_each(function()
    pcall(vim.api.nvim_del_user_command, "Ajans")
  end)

  it("does not export unknown top-level setup options", function()
    setup_config({
      cli = { watch = false },
      extra = true,
    })

    assert.is_false(Config.cli.watch)
    assert.is_nil(Config.extra)
  end)

  it("keeps default mux split options when user split config is not a table", function()
    setup_config({
      cli = {
        mux = {
          split = false,
        },
      },
    })

    assert.are.same({
      vertical = true,
      size = 0.5,
    }, Config.cli.mux.split)
  end)

  it("bounds shared multiplexer scrollback to the Herdr and tmux parity limit", function()
    setup_config({ cli = { mux = { dump = 5000 } } })
    assert.are.equal(1000, Config.cli.mux.dump)

    setup_config({ cli = { mux = { dump = 0 } } })
    assert.are.equal(1, Config.cli.mux.dump)
  end)

  it("bounds fractional split sizes to the shared backend range", function()
    setup_config({ cli = { mux = { split = { size = 0.01 } } } })
    assert.are.equal(0.1, Config.cli.mux.split.size)

    setup_config({ cli = { mux = { split = { size = 1 } } } })
    assert.are.equal(0.9, Config.cli.mux.split.size)

    setup_config({ cli = { mux = { split = { size = 20 } } } })
    assert.are.equal(20, Config.cli.mux.split.size)
  end)

  it("exposes only supported mux options", function()
    local opts = {
      cli = {
        mux = {
          enabled = false,
          backend = "herdr",
          ignored = true,
          create = "split",
          split = {
            vertical = false,
            size = 20,
            extra = true,
          },
          dump = 100,
        },
      },
    }

    setup_config(opts)

    assert.is_nil(Config.cli.mux["enabled"])
    assert.is_nil(Config.cli.mux["ignored"])
    assert.is_nil(Config.cli.mux.split["extra"])
    assert.are.equal("herdr", Config.cli.mux.backend)
    assert.are.equal("split", Config.cli.mux.create)
    assert.are.equal(false, Config.cli.mux.split.vertical)
    assert.are.equal(20, Config.cli.mux.split.size)
    assert.are.equal(100, Config.cli.mux.dump)
    assert.is_false(opts.cli.mux["enabled"])
    assert.are.equal("herdr", opts.cli.mux["backend"])
    assert.is_true(opts.cli.mux["ignored"])
    assert.is_true(opts.cli.mux.split["extra"])
  end)

  it("defaults mux backend selection to auto", function()
    setup_config()

    assert.are.equal("auto", Config.cli.mux.backend)
  end)

  for _, backend in ipairs({ "auto", "tmux", "herdr" }) do
    it("accepts the " .. backend .. " mux backend", function()
      setup_config({ cli = { mux = { backend = backend } } })

      assert.is_true(Config.validate("cli.mux.backend", { "auto", "tmux", "herdr" }))
    end)
  end

  it("rejects unknown mux backends", function()
    setup_config({ cli = { mux = { backend = "screen" } } })

    assert.is_false(Config.validate("cli.mux.backend", { "auto", "tmux", "herdr" }))
  end)
end)
