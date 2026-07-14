---@class ajans.config: ajans.Config
local M = {}

M.ns = vim.api.nvim_create_namespace("ajans.ui")

---@class ajans.Config
local defaults = {
  -- Work with AI cli tools directly from within Neovim
  cli = {
    watch = true, -- notify Neovim of file changes done by AI CLI tools
    ---@class ajans.win.Opts
    win = {
      --- This is run when a new terminal is created, before starting it.
      --- Here you can change window options `terminal.opts`.
      ---@param _ ajans.cli.Terminal
      config = function(_) end,
      wo = {}, ---@type vim.wo
      bo = {}, ---@type vim.bo
      layout = "right", ---@type "float"|"left"|"bottom"|"top"|"right"
      --- Options used when layout is "float"
      ---@type vim.api.keyset.win_config
      float = {
        width = 0.9,
        height = 0.9,
      },
      -- Options used when layout is "left"|"bottom"|"top"|"right"
      ---@type vim.api.keyset.win_config
      split = {
        width = 80, -- set to 0 for default split width
        height = 20, -- set to 0 for default split height
      },
      --- CLI Tool Keymaps (default mode is `t`)
      ---@type table<string, ajans.cli.Keymap|false>
      -- stylua: ignore
      keys = {
        buffers       = { "<c-b>", "buffers"   , mode = "nt", desc = "open buffer picker" },
        files         = { "<c-f>", "files"     , mode = "nt", desc = "open file picker" },
        hide_n        = { "q"    , "hide"      , mode = "n" , desc = "hide the terminal window" },
        hide_ctrl_q   = { "<c-q>", "hide"      , mode = "n" , desc = "hide the terminal window" },
        hide_ctrl_dot = { "<c-.>", "hide"      , mode = "nt", desc = "hide the terminal window" },
        hide_ctrl_z   = { "<c-z>", "blur"      , mode = "nt", desc = "go back to the previous window without hiding the terminal" },
        prompt        = { "<c-p>", "prompt"    , mode = "t" , desc = "insert prompt or context" },
        stopinsert    = { "<c-q>", "stopinsert", mode = "t" , desc = "enter normal mode" },
        normal_cr     = { "<cr>" , "insert_cr" , mode = "n" , desc = "send <cr> to the terminal and enter terminal mode" },
        -- Navigate windows in terminal mode. Only active when:
        -- * layout is not "float"
        -- * there is another window in the direction
        -- With the default layout of "right", only `<c-h>` will be mapped
        nav_left      = { "<c-h>", "nav_left"  , expr = true, desc = "navigate to the left window" },
        nav_down      = { "<c-j>", "nav_down"  , expr = true, desc = "navigate to the below window" },
        nav_up        = { "<c-k>", "nav_up"    , expr = true, desc = "navigate to the above window" },
        nav_right     = { "<c-l>", "nav_right" , expr = true, desc = "navigate to the right window" },
      },
      ---@type fun(dir:"h"|"j"|"k"|"l")?
      --- Function that handles navigation between windows.
      --- Defaults to `vim.cmd.wincmd`. Used by the `nav_*` keymaps.
      nav = nil,
    },
    ---@class ajans.cli.Mux
    mux = {
      -- auto: prefer the usable multiplexer hosting Neovim, then a running Herdr server.
      -- A sole installed Herdr is selected even when invalid so health can report why.
      backend = "auto", ---@type "auto"|"tmux"|"herdr"
      -- terminal: sessions will be attached inside a Neovim terminal
      -- window: create a tmux window or Herdr tab when hosted by the backend
      -- split: create a split when hosted by the backend
      create = "split", ---@type "terminal"|"window"|"split"
      split = {
        vertical = true, -- vertical or horizontal split
        size = 0.5, -- fraction (<= 1), or cells (> 1); each backend validates supported bounds
      },
      -- max lines to capture when dumping a multiplexer pane for scrollback support
      -- more lines means slower loading of the scrollback
      dump = 2000,
    },
    --- Actual cli tool config is loaded from the runtime path `aj/cli/{tool}.lua` and merged with the config below.
    --- For default configs, see https://github.com/sagmans/ajans.nvim/tree/main/aj/cli
    -- stylua: ignore
    ---@type table<string, ajans.cli.Config|{}>
    tools = {
      aider    = {},
      amazon_q = {},
      antigravity = {},
      claude   = {},
      codex    = {},
      copilot  = {},
      crush    = {},
      cursor   = {},
      grok     = {},
      opencode = {},
      pi       = {},
      qwen     = {},
    },
    --- Add custom context. See `lua/ajans/cli/context/init.lua`
    ---@type table<string, ajans.context.Fn>
    context = {},
    -- stylua: ignore
    ---@type table<string, ajans.Prompt|string|fun(ctx:ajans.context.ctx):(string?)>
    prompts = {
      changes         = "Can you review my changes?",
      diagnostics     = "Can you help me fix the diagnostics in {file}?\n{diagnostics}",
      diagnostics_all = "Can you help me fix these diagnostics?\n{diagnostics_all}",
      document        = "Add documentation to {function|line}",
      explain         = "Explain {this}",
      fix             = "Can you fix {this}?",
      optimize        = "How can {this} be optimized?",
      review          = "Can you review {file} for any issues or improvements?",
      tests           = "Can you write tests for {this}?",
      -- simple context prompts
      buffers         = "{buffers}",
      file            = "{file}",
      line            = "{line}",
      position        = "{position}",
      quickfix        = "{quickfix}",
      selection       = "{selection}",
      ["function"]    = "{function}",
      class           = "{class}",
    },
    -- preferred picker for selecting files
    ---@alias ajans.picker "snacks"|"telescope"|"fzf-lua"
    picker = "snacks", ---@type ajans.picker
  },
  ui = {
    -- stylua: ignore
    icons = {
      attached          = " ",
      started           = " ",
      installed         = " ",
      missing           = " ",
      external_attached = "󰖩 ",
      external_started  = "󰖪 ",
      terminal_attached = " ",
      terminal_started  = " ",
    },
  },
  debug = false, -- enable debug logging
}

local state_dir = vim.fn.stdpath("state") .. "/ajans"

local config = vim.deepcopy(defaults) --[[@as ajans.Config]]
M.augroup = vim.api.nvim_create_augroup("ajans", { clear = true })

---@param mux any
---@return any
local function normalize_mux(mux)
  if type(mux) ~= "table" then
    return mux
  end
  local ret = {}
  for key in pairs(defaults.cli.mux) do
    if mux[key] ~= nil then
      ret[key] = vim.deepcopy(mux[key])
    end
  end
  if ret.split ~= nil then
    if type(ret.split) == "table" then
      local split = {}
      for key in pairs(defaults.cli.mux.split) do
        if ret.split[key] ~= nil then
          split[key] = ret.split[key]
        end
      end
      ret.split = split
    else
      ret.split = nil
    end
  end
  return ret
end

---@param name string
function M.state(name)
  return state_dir .. "/" .. name
end

---@param opts? ajans.Config
function M.setup(opts)
  local user = {} ---@type ajans.Config
  for key in pairs(defaults) do
    if opts and opts[key] ~= nil then
      user[key] = vim.deepcopy(opts[key])
    end
  end
  if user.cli and user.cli.mux then
    user.cli.mux = normalize_mux(user.cli.mux)
  end
  config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), user)

  vim.api.nvim_create_user_command("Ajans", function(args)
    require("ajans.commands").cmd(args)
  end, {
    range = true,
    nargs = "?",
    desc = "Ajans",
    complete = function(_, line)
      return require("ajans.commands").complete(line)
    end,
  })

  vim.schedule(function()
    vim.fn.mkdir(state_dir, "p")
    M.set_hl()

    vim.api.nvim_create_autocmd("ColorScheme", {
      group = M.augroup,
      callback = M.set_hl,
    })

    -- Track when a window was last focused
    vim.api.nvim_create_autocmd({ "WinEnter" }, {
      group = M.augroup,
      callback = function()
        local win = vim.api.nvim_get_current_win()
        vim.w[win].ajans_visit = vim.uv.hrtime()
      end,
    })

    require("ajans.status").setup()

    M.validate("cli.win.layout", { "float", "left", "bottom", "top", "right" })
    M.validate("cli.mux.backend", { "auto", "tmux", "herdr" })
    M.validate("cli.mux.create", { "terminal", "window", "split" })
  end)
end

---@param key string
---@param t "string"|"number"|"boolean"|"table"|"function"|any[]
function M.validate(key, t)
  local value = vim.tbl_get(config, unpack(vim.split(key, "%.")))
  local err ---@type string?
  if type(t) == "table" then
    if not vim.tbl_contains(t, value) then
      err = ("Invalid value for option `opts.%s`\n- found: `%s`\n- expected: `%s`"):format(
        key,
        tostring(value),
        table.concat(vim.tbl_map(tostring, t), " | ")
      )
    end
  elseif type(value) ~= t then
    err = ("Expected `opts.%s` to be a `%s`, got `%s`"):format(key, t, type(value))
  end
  if err then
    require("ajans.util").error(err)
    return false
  end
  return true
end

---@param name string
function M.get_tool(name)
  return require("ajans.cli.tool").get(name)
end

function M.tools()
  local ret = {} ---@type table<string, ajans.cli.Tool>
  for name in pairs(M.cli.tools) do
    ret[name] = M.get_tool(name)
  end
  return ret
end

function M.set_hl()
  local links = {
    Chat = "NormalFloat",
    CliMissing = "DiagnosticError",
    CliAttached = "Special",
    CliStarted = "DiagnosticWarn",
    CliInstalled = "DiagnosticOk",
    CliUnavailable = "DiagnosticError",
    LocDelim = "Delimiter",
    LocFile = "@markup.link",
    LocNum = "@attribute",
    LocRow = "AjansLocDelim",
    LocCol = "AjansLocDelim",
  }
  for from, to in pairs(links) do
    vim.api.nvim_set_hl(0, "Ajans" .. from, { link = to, default = true })
  end
end

setmetatable(M, {
  __index = function(_, key)
    return config[key]
  end,
})

return M
