# Configuration

Configure Ajans through `require("ajans").setup(opts)` or your plugin manager's `opts` table.

## Minimal setup

```lua
require("ajans").setup({})
```

With lazy.nvim:

```lua
{
  "sagmans/ajans.nvim",
  opts = {},
}
```

## Default config

This block is generated from `lua/ajans/config.lua` by `./scripts/docs`.

<!-- config:start -->

```lua
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
}
```

<!-- config:end -->

## Common options

### `cli.watch`

`true` by default. When a CLI terminal starts, Ajans watches directories for loaded file buffers and runs `:checktime` after changes. Enable Neovim `autoread` if you want changed files to reload automatically.

### `cli.win`

Controls the Neovim terminal wrapper used to attach to tmux or Herdr sessions.

- `layout`: `"right"`, `"left"`, `"bottom"`, `"top"`, or `"float"`
- `float`: floating-window size/options
- `split`: split size/options
- `wo` / `bo`: local window and buffer options
- `keys`: terminal-window keymaps; see [KEYMAPS.md](./KEYMAPS.md)
- `nav`: custom navigation function for `nav_*` keymaps
- `config`: callback run before a new terminal starts

### `cli.mux`

Controls backend selection and session placement.

- `backend = "auto"`: prefer a usable Herdr when it hosts Neovim, then a usable tmux when it hosts Neovim, then an already-running compatible Herdr server, the sole usable backend, and finally tmux as the compatibility fallback. A sole installed Herdr is selected even when invalid so health can report why.
- `backend = "tmux"` or `"herdr"`: select that backend explicitly
- `create = "terminal"`: attach the persistent session inside a Neovim terminal
- `create = "window"`: when hosted by the backend, create a tmux window or Herdr tab
- `create = "split"`: when hosted by the backend, create a native split
- `split.vertical` and `split.size`: external split direction and size; values at or below `1` are fractions, and larger values are terminal cells. Herdr validates that the result stays within its supported `0.1`-`0.9` layout range.
- `dump`: requested scrollback lines. tmux keeps the configured value; Herdr clamps reads to its `1`-`1000` line limit.

Herdr requires version `>= 0.8.0` on macOS or Linux. Herdr commands inherit `HERDR_SESSION` and `HERDR_SOCKET_PATH`, so named Herdr sessions work without extra Ajans configuration. Native Herdr tab/split creation requires the `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID` values exported by Herdr; splits also require `HERDR_PANE_ID`. `create = "terminal"` needs none of these host IDs. A compatible server remains usable when Herdr recommends restart. Ajans-started servers receive a strict system/runtime environment allowlist; project variables are applied only to each new pane and do not persist in the shared server. Built-in tools recognized by Herdr use its registered-agent launch. Custom commands and unsupported tools fall back to an escaped shell launch in the created pane.

### `cli.tools`

Tool defaults are loaded from runtime files under `aj/cli/{tool}.lua`, then merged with your config.

Example custom tool:

```lua
require("ajans").setup({
  cli = {
    tools = {
      my_tool = {
        cmd = { "my-ai-cli", "--flag" },
        env = {
          MY_TOOL_MODE = "agent",
          NVIM_LOG_FILE = false, -- unset inherited env var
        },
        url = "https://example.com/install-my-ai-cli",
        is_proc = "\\<my-ai-cli\\>",
        keys = {
          prompt = { "<a-p>", "prompt" },
        },
      },
    },
  },
})
```

Supported tool fields include:

- `cmd`: command argv
- `env`: env overrides; `false` unsets a variable
- `url`: install/help URL opened when a missing tool is selected
- `keys`: terminal-window keymaps for this tool
- `is_proc`: process detector string or function
- `format`: formatter run before text is sent
- `native_scroll`: skip Ajans multiplexer scrollback when the tool handles scrolling itself
- `mux_focus`: send a terminal focus event before text input

### `cli.prompts`

Prompts can be strings, `{ msg = "..." }` tables, or functions.

```lua
require("ajans").setup({
  cli = {
    prompts = {
      refactor = "Refactor {selection} for clarity",
      security = "Review {file} for security issues",
      dynamic = function(ctx)
        return "Current buffer: " .. ctx.buf
      end,
    },
  },
})
```

Use prompts with `require("ajans.cli").prompt()` or `:Ajans cli prompt`.

### `cli.context`

Add custom context variables by returning a string, list of strings, Ajans text chunks, or `nil`/`false` when unavailable.

```lua
require("ajans").setup({
  cli = {
    context = {
      cwd = function(ctx)
        return ctx.cwd
      end,
    },
    prompts = {
      where = "Project root: {cwd}",
    },
  },
})
```

Built-in context variables are covered in [USAGE.md](./USAGE.md#context-variables).

### `cli.picker`

Preferred picker for file and buffer selection: `"snacks"`, `"telescope"`, or `"fzf-lua"`. Ajans falls back through configured picker, snacks, telescope, then fzf-lua when opening picker-backed actions.

### `ui.icons`

Status icons used by the CLI selector and status helpers.
