# Architecture

Ajans is a Neovim plugin around local AI CLI tools. It does not implement an AI model. It manages tmux or Herdr sessions, a Neovim terminal wrapper, prompt/context rendering, picker integrations, and status reporting.

## Module map

| Area | Files | Role |
| --- | --- | --- |
| Setup/config | `lua/ajans/init.lua`, `lua/ajans/config.lua` | Merge user config, create `:Ajans`, set highlights, validate options, start status hooks. |
| Commands | `lua/ajans/commands.lua` | Parse `:Ajans cli ...` commands and Lua-style args. |
| CLI API | `lua/ajans/cli/init.lua` | Public API: `select`, `show`, `toggle`, `focus`, `hide`, `close`, `send`, `prompt`, `render`, and memory-only `retry` for undelivered prompts. |
| Tool registry | `lua/ajans/cli/tool.lua`, `aj/cli/*.lua` | Load default tool configs from runtime path and merge user overrides. |
| State | `lua/ajans/cli/state.lua` | Combine installed tools, running sessions, attached sessions, and user filters. |
| Sessions | `lua/ajans/cli/session/init.lua`, `lua/ajans/cli/session/tmux.lua`, `lua/ajans/cli/session/herdr.lua`, `lua/ajans/cli/session/herdr/*.lua` | Backend selection and lifecycle contracts; focused Herdr transport, discovery, layout, and integration-advisory modules. |
| Terminal wrapper | `lua/ajans/cli/terminal.lua`, `lua/ajans/cli/scrollback.lua` | Neovim terminal window/buffer lifecycle, keymaps, send queue, mode restore, scrollback. |
| Context | `lua/ajans/cli/context/*.lua`, `lua/ajans/text.lua`, `lua/ajans/treesitter.lua` | Render prompt variables into strings with optional highlighting metadata. |
| Pickers | `lua/ajans/cli/picker/*.lua`, `lua/ajans/cli/ui/*.lua` | Tool/prompt/file/buffer selection through `vim.ui.select`, snacks, Telescope, or fzf-lua. |
| Watch | `lua/ajans/cli/watch.lua` | Watch loaded file directories and run `:checktime`. |
| Status | `lua/ajans/status.lua` | Cache attached CLI sessions for statuslines. |
| Health | `lua/ajans/health.lua` | Check Neovim, `autoread`, the selected backend/version/server, process tools when tmux needs them, and CLI executables. |
| Docs | `lua/ajans/docs.lua`, `tests/fixtures/readme.lua` | Generate reference blocks for docs. |

## Startup flow

1. User calls `require("ajans").setup(opts)`.
2. `config.setup` merges defaults with user config.
3. Ajans creates the `:Ajans` user command.
4. Scheduled setup creates state dir, highlights, autocmds, status hooks, and option validation.

## Command and API flow

```text
:Ajans cli send msg="{selection}"
        │
        ▼
lua/ajans/commands.lua parses module/command/args
        │
        ▼
require("ajans.cli").send(opts)
        │
        ▼
context renderer expands prompt variables
        │
        ▼
state layer selects/attaches a session
        │
        ▼
tool formatter adapts text for target CLI
        │
        ▼
selected tmux or Herdr backend sends text to pane
```

## Tool loading

For each configured tool name, Ajans looks for `aj/cli/{name}.lua` on the runtime path. The runtime default and user config are deep-merged. Tool configs define command argv, process detection, URLs, key overrides, formatting, and scroll/focus behavior.

Bundled tool configs live in `aj/cli/`.

## Session model

Ajans resolves one active backend during session setup. Explicit `tmux` or `herdr` configuration wins. Auto-selection considers the host environment, a running compatible Herdr server, and installed executables.

- New sessions get stable names from tool name plus cwd hash.
- The tmux adapter discovers panes with `tmux list-panes` and inspects process trees with `ps`, `/proc`, and `lsof` where available.
- The Herdr adapter uses the `api snapshot` inventory available in supported Herdr releases. Stable Ajans names and Herdr labels classify known tools first; bounded process inspection is reserved for unmatched custom tools. It keeps Herdr terminal, pane, tab, workspace, and available process identities.
- Herdr control calls use bounded execution and decoded JSON errors. Sensitive pane creation, launch, and prompt payloads use Herdr's owner-only local newline-delimited JSON socket instead of process arguments; Ajans connects through the canonical path it validated. Ajans starts a persistent server with a strict system/runtime environment allowlist so project secrets do not persist, then applies the current process environment only when creating each pane. Registered tools use Herdr's pane-first agent launch; custom commands use escaped shell fallback. This intentionally means other consumers of an Ajans-started shared server do not inherit arbitrary variables. Workspace, tab, pane, and nested-layout changes use validated transactional cleanup.
- If Neovim is hosted by the selected backend, `window` maps to a tmux window or Herdr tab and `split` maps to a native pane split.
- Backend `start()` returns `(terminal_command, started)`: `started` is the authoritative creation outcome, while an optional command requests a Neovim terminal wrapper. Discovery returns `(sessions, authoritative)`, so transient scans retain known sessions and authoritative scans remove stale wrappers.
- Deterministic agent names let Herdr starts reuse an existing owned agent for the same tool and cwd; an `agent_name_taken` race closes only the freshly created empty shell, then adopts the winner after strict name, kind, cwd, and resource-id validation. Foreign conflicts fail closed with a manual inspection command instead of reuse or cleanup.
- Tools can declare `mux_ready` screen markers (`required`/`blocked`) checked against the visible pane before automated input is authorized; this keeps prompts out of settling TUIs such as Agy's sign-in and folder-trust screens.
- The Herdr integration advisor reads `herdr integration status` for `pi` and `antigravity-cli`, warns once per changed state with the exact install command, and never installs hooks or blocks sessions.
- Prompt delivery failures (send or submit) are retained in memory only, bound to session identity, tool, and failed phase; `require("ajans.cli").retry(opts)` redelivers explicitly and refuses after detach, identity, tool, or authorization changes. Submit-phase retry sends only Enter so prompt text is never duplicated.
- Embedded terminal sessions attach to the persistent backend resource and are tracked as `terminal: ...` wrappers. Stable backend identity removes duplicate parent/wrapper entries and reconciles server restarts. Automated input additionally pins the foreground process incarnation; detach or replacement invalidates delayed authorization before delivery.

## Terminal wrapper

The wrapper is a Neovim terminal buffer/window that attaches to a tmux or Herdr session.

It handles:

- split/float layout
- buffer-local terminal keymaps
- terminal/normal mode restore
- delayed send queue while the CLI initializes
- cleanup on terminal close
- optional backend scrollback capture when entering normal mode or using mouse scroll

## Context renderer

Prompt templates contain variables like `{selection}` or `{diagnostics}`. Rendering happens through `lua/ajans/cli/context/init.lua`.

Important boundary: location variables (`{file}`, `{line}`, `{position}`, `{this}` in file buffers) render file references, not whole file contents. Text content comes from `{selection}` or custom context providers.

## Watch and reload

When enabled, file watching starts when a CLI terminal starts and stops when all Ajans terminals close. Ajans watches directories for loaded file buffers, records changed paths, and runs `:checktime`. Neovim `autoread` controls automatic reload behavior.

## Events and status

Session attach/detach emits user autocmds:

- `User AjansCliAttach`
- `User AjansCliDetach`

`lua/ajans/status.lua` listens to those events and exposes `require("ajans.status").cli()` for statusline integrations. Periodic liveness refreshes are asynchronous, so statusline rendering only reads cached data.

## Boundaries

- No hosted service dependency.
- No bundled AI model.
- One selected local session backend at a time: tmux or Herdr.
- No automatic whole-file context unless you add custom context.
