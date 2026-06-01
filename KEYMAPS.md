# Keymaps

Ajans does not create global user keymaps by itself. Add the mappings you want through your plugin manager or `vim.keymap.set`.

## Suggested lazy.nvim mappings

Generated from `tests/fixtures/readme.lua` by `./scripts/docs`.

<!-- setup_base:start -->

```lua
{
  "sagmans/ajans.nvim",
  opts = {
    -- add any options here
  },
  keys = {
    {
      "<c-.>",
      function() require("ajans.cli").focus() end,
      desc = "Ajans Focus",
      mode = { "n", "t", "i", "x" },
    },
    {
      "<leader>aa",
      function() require("ajans.cli").toggle() end,
      desc = "Ajans Toggle CLI",
    },
    {
      "<leader>as",
      function() require("ajans.cli").select() end,
      -- Or to select only installed tools:
      -- require("ajans.cli").select({ filter = { installed = true } })
      desc = "Select CLI",
    },
    {
      "<leader>ad",
      function() require("ajans.cli").close() end,
      desc = "Detach a CLI Session",
    },
    {
      "<leader>at",
      function() require("ajans.cli").send({ msg = "{this}" }) end,
      mode = { "x", "n" },
      desc = "Send This",
    },
    {
      "<leader>af",
      function() require("ajans.cli").send({ msg = "{file}" }) end,
      desc = "Send File",
    },
    {
      "<leader>av",
      function() require("ajans.cli").send({ msg = "{selection}" }) end,
      mode = { "x" },
      desc = "Send Visual Selection",
    },
    {
      "<leader>ap",
      function() require("ajans.cli").prompt() end,
      mode = { "n", "x" },
      desc = "Ajans Select Prompt",
    },
    -- Example of a keybinding to open Claude directly
    {
      "<leader>ac",
      function() require("ajans.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Ajans Toggle Claude",
    },
  },
}
```

<!-- setup_base:end -->

## Default terminal-window keymaps

These mappings are buffer-local to Ajans CLI terminal buffers. Source: `lua/ajans/config.lua`.

| Name | Key | Modes | Action |
| --- | --- | --- | --- |
| `buffers` | `<c-b>` | normal, terminal | Open buffer picker and send selected locations. |
| `files` | `<c-f>` | normal, terminal | Open file picker and send selected locations. |
| `hide_n` | `q` | normal | Hide terminal window. |
| `hide_ctrl_q` | `<c-q>` | normal | Hide terminal window. |
| `hide_ctrl_dot` | `<c-.>` | normal, terminal | Hide terminal window. |
| `hide_ctrl_z` | `<c-z>` | normal, terminal | Blur terminal and return to previous window. |
| `prompt` | `<c-p>` | terminal | Select prompt/context and insert it into the CLI. |
| `stopinsert` | `<c-q>` | terminal | Enter normal mode. Press `<c-q>` again in normal mode to hide. |
| `normal_cr` | `<cr>` | normal | Send Enter to the terminal and enter terminal mode. |
| `nav_left` | `<c-h>` | terminal | Move to left Neovim window when possible. |
| `nav_down` | `<c-j>` | terminal | Move to lower Neovim window when possible. |
| `nav_up` | `<c-k>` | terminal | Move to upper Neovim window when possible. |
| `nav_right` | `<c-l>` | terminal | Move to right Neovim window when possible. |

Navigation mappings only move between Neovim windows when the CLI layout is not `"float"` and another window exists in that direction. Otherwise Ajans passes the original control key through to the terminal.

## Override terminal keymaps

```lua
require("ajans").setup({
  cli = {
    win = {
      keys = {
        -- change a default mapping
        hide_n = { "<leader>q", "hide", mode = "n" },

        -- disable a default mapping
        hide_ctrl_dot = false,

        -- add a custom mapping
        say_hi = {
          "<c-g>",
          function(t)
            t:send("hi!\n")
          end,
          mode = "t",
          desc = "Send hi",
        },
      },
    },
  },
})
```

## Tool-specific keymaps

Tool config keymaps merge over `cli.win.keys`.

```lua
require("ajans").setup({
  cli = {
    tools = {
      opencode = {
        keys = {
          prompt = { "<a-p>", "prompt" },
        },
      },
    },
  },
})
```

Bundled defaults currently override the prompt mapping for `crush` and `opencode` to `<a-p>`.
