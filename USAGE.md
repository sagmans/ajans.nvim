# Usage

Ajans centers on one workflow: use keymaps to select a persistent tmux- or Herdr-backed AI CLI, attach to it, then send editor context.

Ajans does not create global keymaps by itself. The examples below assume the suggested mappings from [KEYMAPS.md](./KEYMAPS.md).

## Backend selection

`cli.mux.backend = "auto"` is the default. Auto-selection prefers a usable multiplexer hosting Neovim, then a running compatible Herdr server, the sole usable backend, and tmux as the compatibility fallback. If Herdr is the only installed backend, Ajans selects it even when validation fails so `:checkhealth ajans` can report the cause. Use `"tmux"` or `"herdr"` for an explicit choice.

Herdr `>= 0.8.0` is supported on macOS and Linux. When Neovim runs inside Herdr, Ajans maps `create = "window"` to a Herdr tab and `create = "split"` to a Herdr pane split. Native tabs use `HERDR_WORKSPACE_ID` and `HERDR_TAB_ID`; splits also use `HERDR_PANE_ID`. Herdr exports these values to hosted panes. Named sessions selected with `HERDR_SESSION` or `HERDR_SOCKET_PATH` are inherited automatically. A running server with a compatible protocol remains usable when Herdr recommends a client-version restart; `:checkhealth ajans` reports that recommendation without blocking sessions.

Herdr agents get deterministic `ajans-<tool>-<cwd-hash>` names. Starting a tool again for the same working directory reuses the existing agent instead of creating a duplicate; if another process claims the name first, Ajans closes only the empty pane it created, re-validates the winner, and attaches to it. A conflicting agent that does not match Ajans's tool, kind, and working directory is never reused or closed; Ajans reports the exact `herdr agent get` command so you can inspect it manually.

When Ajans starts Herdr, it gives the long-lived shared server a strict allowlist of system/runtime variables rather than persisting the full Neovim project environment. Ajans applies the current launch environment only when creating each pane through the trusted local socket. Built-in tools recognized by Herdr use its registered-agent launch; custom commands and unsupported tools use an escaped shell launch in the created pane. Other Herdr consumers that require variables such as `SSH_AUTH_SOCK`, proxy settings, editor settings, or custom plugin variables should start the shared Herdr server themselves with their chosen environment before Ajans creates a session.

## Keymap-first workflow

1. Select or start a tool with `<leader>as`.

   This finds supported CLI tools and attaches to an existing session in the selected backend when one is already running.

2. Toggle the CLI view with `<leader>aa`.

   For `create = "terminal"`, Ajans opens a Neovim terminal wrapper attached to the persistent multiplexer session. Native windows/tabs and splits remain external to Neovim. In either case, the AI CLI keeps running in tmux or Herdr.

3. Send context from your editor.

   | Key | Mode | Sends |
   | --- | --- | --- |
   | `<leader>at` | normal, visual | `{this}`: current location, or selection from non-file buffers |
   | `<leader>af` | normal | `{file}`: current file location |
   | `<leader>av` | visual | `{selection}`: selected text |
   | `<leader>ap` | normal, visual | prompt picker |

4. Work inside the CLI terminal wrapper when needed.

   | Key | Mode | Action |
   | --- | --- | --- |
   | `<c-.>` | normal, terminal, insert, visual | focus/hide Ajans |
   | `<c-p>` | terminal | insert prompt or context |
   | `<c-f>` | normal, terminal | pick files and send locations |
   | `<c-b>` | normal, terminal | pick buffers and send locations |
   | `<c-q>` | terminal | enter terminal normal mode |
   | `<c-q>` or `q` | normal | hide terminal wrapper |

Use [KEYMAPS.md](./KEYMAPS.md) for full suggested mappings and default terminal-window mappings.

## Command reference

Ajans exposes one command namespace:

```vim
:Ajans cli <command> [args]
```

Arguments are Lua-style assignments:

```vim
:Ajans cli show name=claude focus=true
:Ajans cli send msg="{selection}"
:'<,'>Ajans cli send msg="{selection}"
```

Available CLI commands:

- `show`
- `toggle`
- `hide`
- `close`
- `focus`
- `select`
- `send`
- `prompt`
- `retry`

## Lua API reference

Generated from `lua/ajans/cli/init.lua` by `./scripts/docs`.

<!-- api_cli:start -->

<table><tr><th>Cmd</th><th>Lua</th></tr>
<tr><td> Forget any retained prompt without redelivering it</td><td>


```lua
require("ajans.cli").clear_retry()
```

</td></tr>
<tr><td><code>:Ajans cli close</code> </td><td>


```lua
---@param opts? ajans.cli.Hide
---@overload fun(name: string)
require("ajans.cli").close(opts)
```

</td></tr>
<tr><td><code>:Ajans cli focus</code> Toggle focus of the terminal window if it is already open</td><td>


```lua
---@param opts? ajans.cli.Show
---@overload fun(name: string)
require("ajans.cli").focus(opts)
```

</td></tr>
<tr><td><code>:Ajans cli hide</code> </td><td>


```lua
---@param opts? ajans.cli.Hide
---@overload fun(name: string)
require("ajans.cli").hide(opts)
```

</td></tr>
<tr><td><code>:Ajans cli prompt</code> Select a prompt to send</td><td>


```lua
---@param opts? ajans.cli.Prompt|{cb:nil}
---@overload fun(cb:fun(msg?:string))
require("ajans.cli").prompt(opts)
```

</td></tr>
<tr><td> Render a message template or prompt</td><td>


```lua
---@param opts? ajans.cli.Message|string
require("ajans.cli").render(opts)
```

</td></tr>
<tr><td><code>:Ajans cli retry</code> Redeliver the most recently failed prompt. Never automatic: the user must
invoke it after resolving the agent pane. Refuses after the bound session
identity, tool, or process ownership changed.</td><td>


```lua
---@param opts? {name?:string, filter?:ajans.cli.Filter}
require("ajans.cli").retry(opts)
```

</td></tr>
<tr><td><code>:Ajans cli select</code> Start or attach to a CLI tool</td><td>


```lua
---@param opts? ajans.cli.Select|{cb:nil}|{focus?:boolean}
---@overload fun(cb:fun(state?:ajans.cli.State))
require("ajans.cli").select(opts)
```

</td></tr>
<tr><td><code>:Ajans cli send</code> Send a message or prompt to a CLI</td><td>


```lua
---@param opts? ajans.cli.Send
---@overload fun(msg:string)
require("ajans.cli").send(opts)
```

</td></tr>
<tr><td><code>:Ajans cli show</code> </td><td>


```lua
---@param opts? ajans.cli.Show
---@overload fun(name: string)
require("ajans.cli").show(opts)
```

</td></tr>
<tr><td><code>:Ajans cli toggle</code> </td><td>


```lua
---@param opts? ajans.cli.Show
---@overload fun(name: string)
require("ajans.cli").toggle(opts)
```

</td></tr>
</table>

<!-- api_cli:end -->

## Context variables

Context variables render inside prompt strings.

| Variable | Meaning |
| --- | --- |
| `{position}` | Current file location with line and column. |
| `{file}` | Current file location only. |
| `{line}` | Current file line location. |
| `{buffers}` | Listed file buffers as locations. |
| `{diagnostics}` | Diagnostics for current buffer; limited to visual range when a range exists. |
| `{diagnostics_all}` | Diagnostics across all buffers. |
| `{quickfix}` | Current quickfix list with locations and messages. |
| `{selection}` | Current visual selection text. |
| `{function}` | Function textobject location at cursor; requires `nvim-treesitter-textobjects`. |
| `{class}` | Class textobject location at cursor; requires `nvim-treesitter-textobjects`. |
| `{this}` | Special variable: file buffers resolve to `{position}`; non-file buffers resolve to literal `this` plus `{selection}`. |

Use fallbacks when a context may be unavailable:

```text
{function|line}
{class|file}
```

Use `{selection}` when you want code text. `{file}`, `{line}`, `{position}`, and `{this}` send locations, not whole file contents.

## Built-in prompts

Defined in `lua/ajans/config.lua`:

| Prompt | Template |
| --- | --- |
| `changes` | `Can you review my changes?` |
| `diagnostics` | `Can you help me fix the diagnostics in {file}?\n{diagnostics}` |
| `diagnostics_all` | `Can you help me fix these diagnostics?\n{diagnostics_all}` |
| `document` | <code>Add documentation to {function&#124;line}</code> |
| `explain` | `Explain {this}` |
| `fix` | `Can you fix {this}?` |
| `optimize` | `How can {this} be optimized?` |
| `review` | `Can you review {file} for any issues or improvements?` |
| `tests` | `Can you write tests for {this}?` |

Simple context prompts also exist for `buffers`, `file`, `line`, `position`, `quickfix`, `selection`, `function`, and `class`.

## Pickers

Ajans can use snacks.nvim, Telescope, or fzf-lua for file and buffer picker actions.

Inside the CLI terminal wrapper:

- `<c-f>` opens a file picker and sends selected file locations.
- `<c-b>` opens a buffer picker and sends selected buffer locations.

### Snacks picker action

Generated from `tests/fixtures/readme.lua` by `./scripts/docs`.

<!-- snacks_picker:start -->

```lua
{
  "folke/snacks.nvim",
  optional = true,
  opts = {
    picker = {
      actions = {
        ajans_send = function(...)
          return require("ajans.cli.picker.snacks").send(...)
        end,
      },
      win = {
        input = {
          keys = {
            ["<a-a>"] = {
              "ajans_send",
              mode = { "n", "i" },
            },
          },
        },
      },
    },
  },
}
```

<!-- snacks_picker:end -->

With that config, `<a-a>` in a Snacks picker sends selected items to the active CLI session.

## Statusline

`require("ajans.status").cli()` returns attached CLI sessions as tables with `id`, `tool`, `cwd`, `backend`, `external`, `terminal`, and optional `identity`. `backend` is `"tmux"` or `"herdr"`; `external` identifies native multiplexer panes, `terminal` identifies Neovim attachment wrappers, and `identity` is the stable backend resource when available.

Generated lualine example:

<!-- setup_lualine:start -->

```lua
{
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    opts.sections = opts.sections or {}
    opts.sections.lualine_x = opts.sections.lualine_x or {}

    -- CLI session status
    table.insert(opts.sections.lualine_x, 2, {
      function()
        local status = require("ajans.status").cli()
        return " " .. (#status > 1 and #status or "")
      end,
      cond = function()
        return #require("ajans.status").cli() > 0
      end,
      color = function()
        return "Special"
      end,
    })
  end,
}
```

<!-- setup_lualine:end -->

## File watching

When `cli.watch = true`, Ajans watches directories for loaded file buffers while CLI terminals are active. On file-system changes, it runs `:checktime`.

For automatic reloads, enable Neovim `autoread`:

```vim
:set autoread
```

## Troubleshooting

### Tool missing

1. Run `:checkhealth ajans`.
2. Verify executable exists, for example `which claude`.
3. Try running the CLI directly outside Neovim.
4. Check `:messages`.

### Session not persisting

1. Run `:checkhealth ajans` and confirm the intended backend was selected.
2. For tmux, verify `tmux` is installed.
3. For Herdr, verify `herdr --version` reports `0.8.0` or newer and confirm health reports a trusted owner-only local API socket. A compatible version mismatch is advisory; protocol incompatibility blocks use. Before restarting, save active pane work: a restart stops the original shells, agents, tests, and other pane processes. Prefer Herdr's supported live handoff when available; see [Herdr session state and recovery](https://herdr.dev/docs/session-state/).
4. Set `cli.mux.backend` explicitly if auto-selection chose a different installed backend.

### Prompt not delivered

Ajans never types into an agent it cannot verify. For Antigravity, Ajans waits up to 15 seconds for Agy's stable input footer. Boot, sign-in, trust, and unreadable screens make authorization fail. Ajans creates no retry record because it did not attempt delivery.

If a pane send or submit fails after authorization, Ajans keeps the latest formatted prompt in memory. A new delivery failure replaces the previous record.

1. Inspect the agent pane and resolve the blocking screen.
2. If Ajans reports `Refusing to send`, repeat the original send after the pane is ready.
3. If Ajans reports `Delivery to the agent failed`, run `:checkhealth ajans`.
4. Run `:Ajans cli retry name=<tool>` after you resolve the failure.

Retry refuses after the session, tool, or process identity changes. A retry after a failed submit sends only Enter.

### Herdr integration warnings

For `antigravity`, Ajans also holds automated input until Agy's own screen settles: sign-in restoration and folder-trust screens swallow typed text, so prompts wait for the stable input footer instead. If Agy shows a trust screen, approve it manually once; Ajans never approves trust prompts.

For `pi` and `antigravity`, Ajans reads `herdr integration status` and warns once when the integration is missing or stale, including the exact `herdr integration install` command. Integrations improve agent lifecycle reporting only; they never sign in, trust folders, or authorize terminal input. Ajans never installs or modifies them itself.

### Picker action fails

Install one supported picker or set `cli.picker` to one you have installed: `"snacks"`, `"telescope"`, or `"fzf-lua"`.

### Function/class context empty

Install `nvim-treesitter-textobjects` on its `main` branch and ensure the current filetype has textobject queries.
