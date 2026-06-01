# ajans.nvim

Tmux-first Neovim sidecar for AI CLI tools.

`ajans.nvim` is a simplified fork of [sidekick.nvim](https://github.com/folke/sidekick.nvim). It keeps the scope narrow: run local AI CLIs through tmux, send editor context, and keep sessions alive across Neovim restarts.

Ajans is tmux-only. AI agents run in tmux sessions/panes, not as Neovim jobs. Neovim attaches through a lightweight terminal wrapper; when Neovim is already inside tmux, Ajans can also use native tmux splits or windows.

## What it does

- Runs supported AI CLI tools through tmux sessions and panes.
- Opens a Neovim terminal wrapper that attaches to tmux when you want the session inside Neovim.
- Reuses tmux sessions so CLI work survives window changes and Neovim restarts.
- Sends verified editor context: file locations, cursor/range positions, selections, diagnostics, quickfix entries, buffers, functions, and classes.
- Provides prompt, tool, file, and buffer pickers.
- Watches loaded file directories and runs `:checktime` after external changes; enable `autoread` for automatic reloads.
- Exposes small Lua APIs for keymaps, picker integrations, and statuslines.

## Requirements

- Neovim `>= 0.11.2`
- [tmux](https://github.com/tmux/tmux/wiki)
- One or more AI CLI tools, such as Claude, Codex, Copilot, Antigravity, Opencode, or Qwen
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim), Telescope, or fzf-lua for picker workflows
- Optional: [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) for `{function}` and `{class}` context
- Optional on Unix-like systems: `ps` and `lsof` for running-session discovery

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "sagmans/ajans.nvim",
  opts = {},
}
```

Then run:

```vim
:checkhealth ajans
```

Add your preferred mappings from [KEYMAPS.md](./KEYMAPS.md).

## Quick start

After adding mappings from [KEYMAPS.md](./KEYMAPS.md):

- `<leader>as` selects or starts a tmux-backed AI CLI session.
- `<leader>aa` toggles the Neovim terminal wrapper attached to that session.
- `<leader>at`, `<leader>af`, and `<leader>av` send current context.
- `<leader>ap` opens the prompt/context picker.

Use `{selection}` when you want to send selected code. Use `{file}`, `{line}`, `{position}`, or `{this}` when you want to send location context. Command and Lua API equivalents live in [USAGE.md](./USAGE.md).

## Supported CLI tools

Ajans ships default configs for:

`aider`, `amazon_q`, `antigravity`, `claude`, `codex`, `copilot`, `crush`, `cursor`, `grok`, `opencode`, `pi`, and `qwen`.

Run `:checkhealth ajans` to see which tools are installed.

## Documentation

- [USAGE.md](./USAGE.md) — keymap-first workflow, commands, prompts, context variables, pickers, statusline, troubleshooting
- [CONFIG.md](./CONFIG.md) — setup options, tool config, custom prompts, custom context
- [KEYMAPS.md](./KEYMAPS.md) — suggested user mappings and default terminal mappings
- [ARCHITECTURE.md](./ARCHITECTURE.md) — internals and data flow
- [DEVELOPMENT.md](./DEVELOPMENT.md) — contributor workflow and validation
- `:help ajans.nvim` — in-editor Vim help reference from [`doc/ajans.nvim.txt`](./doc/ajans.nvim.txt)

## Scope

Ajans is not an AI model, completion engine, or hosted agent service. It connects Neovim to local CLI tools you install and configure.
