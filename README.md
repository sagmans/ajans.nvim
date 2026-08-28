# ajans.nvim

Multiplexer-backed Neovim sidecar for AI CLI tools.

`ajans.nvim` is a simplified fork of [sidekick.nvim](https://github.com/folke/sidekick.nvim). It keeps the scope narrow: run local AI CLIs through tmux or Herdr, send editor context, and keep sessions alive across Neovim restarts.

Ajans supports tmux and [Herdr](https://herdr.dev) as full session backends. AI agents run in multiplexer sessions or panes, not as Neovim jobs. Neovim attaches through a lightweight terminal wrapper; when Neovim already runs inside the selected multiplexer, Ajans can also create native windows, tabs, or splits.

## What it does

- Runs supported AI CLI tools through tmux or Herdr sessions and panes.
- Opens a Neovim terminal wrapper for embedded sessions, or uses native backend windows/tabs and splits when configured.
- Reuses persistent sessions across window changes and Neovim restarts.
- Discovers supported and custom configured tools already running in multiplexer panes.
- Sends verified editor context: file locations, cursor/range positions, selections, diagnostics, quickfix entries, buffers, functions, and classes.
- Provides prompt, tool, file, and buffer pickers.
- Watches loaded file directories and runs `:checktime` after external changes; enable `autoread` for automatic reloads.
- Exposes small Lua APIs for keymaps, picker integrations, and statuslines.

## Requirements

- Neovim `>= 0.11.2`
- One supported session backend:
  - [tmux](https://github.com/tmux/tmux/wiki), or
  - [Herdr](https://herdr.dev) `>= 0.8.0` on macOS or Linux
- One or more AI CLI tools, such as Claude, Codex, Copilot, Antigravity, Opencode, or Qwen
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim), Telescope, or fzf-lua for picker workflows
- Optional: [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) for `{function}` and `{class}` context
- Optional with tmux: Linux uses `ps` or `/proc` for process discovery and `/proc` for working directories; other Unix systems use `ps` for discovery and optionally `lsof` for working directories

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "sagmans/ajans.nvim",
  opts = {},
}
```

Ajans selects the backend automatically by default. Set `cli.mux.backend` to `"tmux"` or `"herdr"` to choose explicitly. Then run:

```vim
:checkhealth ajans
```

Add your preferred mappings from [KEYMAPS.md](./KEYMAPS.md).

## Quick start

After adding mappings from [KEYMAPS.md](./KEYMAPS.md):

- `<leader>as` selects or starts a persistent AI CLI session.
- `<leader>aa` toggles an embedded terminal wrapper; native backend tabs/splits remain external.
- `<leader>at`, `<leader>af`, and `<leader>av` send current context.
- `<leader>ap` opens the prompt/context picker.

Use `{selection}` when you want to send selected code. Use `{file}`, `{line}`, `{position}`, or `{this}` when you want to send location context. Command and Lua API equivalents live in [USAGE.md](./USAGE.md).

## Supported CLI tools

Ajans ships default configs for:

`aider`, `amazon_q`, `antigravity`, `claude`, `codex`, `copilot`, `crush`, `cursor`, `grok`, `opencode`, `pi`, and `qwen`.

Run `:checkhealth ajans` to see which tools are installed.

## Documentation

- [USAGE.md](./USAGE.md) — keymap-first workflow, commands, prompts, context variables, pickers, statusline, troubleshooting
- [CONFIG.md](./CONFIG.md) — setup options, backend selection, tool config, custom prompts, custom context
- [KEYMAPS.md](./KEYMAPS.md) — suggested user mappings and default terminal mappings
- [ARCHITECTURE.md](./ARCHITECTURE.md) — internals and data flow
- [DEVELOPMENT.md](./DEVELOPMENT.md) — contributor workflow and validation
- `:help ajans.nvim` — in-editor Vim help reference from [`doc/ajans.nvim.txt`](./doc/ajans.nvim.txt)

## Scope

Ajans is not an AI model, completion engine, or hosted agent service. It connects Neovim to local CLI tools you install and configure.
