# Herdr backend support plan

## Context

Ajans currently hardcodes tmux as its only session backend. This worktree is named `feat-herdr-backend`, and the requested outcome is full functional parity between Herdr and tmux on macOS/Linux, while preserving the existing tmux workflow. Herdr support is not complete if any Ajans operation available with tmux is missing or degraded.

Known constraints from the current implementation:

- `lua/ajans/cli/session/init.lua` always constructs tmux sessions and rejects non-tmux backend registration.
- `lua/ajans/cli/terminal.lua` only accepts terminal wrappers whose multiplexer backend is tmux.
- `lua/ajans/config.lua`, health checks, tests, and user documentation all describe tmux as mandatory.
- Backend-neutral session lifecycle methods already exist (`start`, `attach`, `detach`, `sessions`, `send`, `submit`, `dump`, `is_running`), but backend selection is not yet configurable.
- Attached-session de-duplication currently relies on overlapping tmux pane/client PIDs; Herdr exposes stable agent/terminal/pane IDs instead, so identity-based de-duplication is needed.

Herdr’s current CLI/socket API provides the required primitives:

- `herdr agent start ... -- <argv...>` launches argv directly and returns stable `terminal_id`, `pane_id`, workspace/tab IDs, cwd, and agent identity.
- `herdr agent list/get/send/attach` covers discovery, liveness/identity, literal input, and direct terminal attachment.
- `herdr pane send-keys ... enter` covers submission; `pane read --source recent --lines N --ansi` covers scrollback.
- `herdr pane process-info` exposes foreground PIDs/argv/cwd for matching configured Ajans tools, including custom tools.
- Herdr named sessions are selected through its standard `--session`/`HERDR_SESSION` mechanism; Ajans can use the selected Herdr namespace without inventing another persistence layer.
- Herdr models external placement as workspaces, tabs, and pane splits rather than tmux windows/splits; Ajans must map its existing `create` modes deliberately.
- Require Herdr `>= 0.7.0`: that release includes direct agent argv launch with per-process environment, direct terminal attach, pane input/read commands, and `pane process-info`, which together are needed for parity.

## Approach

Add full support for [`ogulcancelik/herdr`](https://github.com/ogulcancelik/herdr) while retaining tmux. Add `cli.mux.backend = "auto" | "tmux" | "herdr"`; explicit values are authoritative. In `auto`, resolve deterministically in this order: Herdr hosting Neovim (`HERDR_ENV=1`), tmux hosting Neovim (`TMUX`), an already-running Herdr server, the sole installed backend, then tmux as the compatibility tie-breaker when both are merely installed. Resolve one active backend at setup/session initialization rather than combining sessions from two independent namespaces.

Preserve the existing session interface and tmux behavior. Implement Herdr through its JSON-producing CLI wrappers (not a bespoke socket client), add a Herdr backend, and generalize the terminal wrapper plus state/UI code only where needed. Represent an Ajans session as one Herdr agent/terminal/pane. Use direct argv launch and stable Herdr IDs; use direct terminal attach for the embedded Neovim terminal path and Herdr workspace/tab/split placement for external creation.

Map creation modes as follows:

- Outside a Herdr-hosted Neovim, create an Ajans-owned Herdr workspace for the agent and attach it through the existing Neovim terminal wrapper.
- Inside Herdr with `create = "terminal"`, likewise isolate the agent in its own workspace, then direct-attach inside Neovim instead of duplicating it beside Neovim’s Herdr pane.
- Inside Herdr with `create = "window"`, create a Herdr tab, launch the agent there, and remove the temporary root shell pane.
- Inside Herdr with `create = "split"`, launch the agent as a right/down split in the current `HERDR_WORKSPACE_ID`/`HERDR_TAB_ID` according to `split.vertical`, then apply `split.size` through Herdr’s public `pane resize` CLI.

For workspace/tab creation, launch argv via `agent start`, close the temporary shell pane only after success, and roll back the created workspace/tab on failure. Herdr’s `agent start` does not accept an initial ratio, but the CLI does expose `pane resize --pane ID --direction ... --amount ...` and `pane layout`. After the default 50/50 agent split, compute the delta/direction needed for fractional sizes; for cell sizes, use the returned layout’s immediate containing split dimensions to convert cells to a fraction. This preserves `split.size` without a raw socket client.

### Parity contract

The Herdr backend must satisfy every current tmux-backed Ajans behavior:

| Capability | Required Herdr behavior |
| --- | --- |
| Discovery | Find running supported and user-configured tools across all Herdr panes, including panes Herdr has not classified as agents, by combining `api snapshot`/pane inventory with `pane process-info` and existing `Tool:is_proc` matchers. |
| Stable identity | Preserve one stable Ajans session per tool/cwd and retain Herdr terminal, pane, tab, and workspace IDs across refreshes and attachments. |
| Creation | Support embedded terminal, external window-equivalent (Herdr tab), and external split creation with cwd, argv, environment sets/unsets, orientation, and configured size. |
| Lifecycle | Start Herdr on demand, detect liveness, attach, detach/hide, reopen, survive Neovim restarts, and cleanly recover from a disappeared pane or partial creation failure without killing persistent agent sessions on ordinary Ajans detach/close. |
| Input | Preserve ordered literal and multiline sends, tool-specific formatting/focus behavior, and separate Enter submission. |
| Display | Reuse the Neovim terminal wrapper, correctly distinguish terminal/external sessions in pickers/status, and avoid duplicate parent/wrapper entries. |
| Scrollback | Return ANSI-preserving pane history honoring `cli.mux.dump`, with the same native-scroll opt-out behavior. |
| Existing sessions | Attach to Herdr agents started outside Ajans as well as Ajans-owned agents, including custom configured tools detected from process metadata. |
| Namespaces/errors | Respect Herdr’s selected default/named session environment and provide equivalent missing-backend, startup, command, malformed-response, and stale-session diagnostics. |

macOS/Linux and Herdr `>= 0.7.0` are prerequisites. Windows is the only explicitly excluded platform. No other backend caveat or unsupported Ajans feature is acceptable for completion.

## Files to modify

Critical areas:

- `lua/ajans/cli/session/init.lua`
- `lua/ajans/cli/session/herdr.lua` (new)
- `lua/ajans/cli/terminal.lua`
- `lua/ajans/cli/state.lua`
- `lua/ajans/config.lua`
- `lua/ajans/health.lua`
- `tests/session_spec.lua`
- `tests/config_spec.lua`
- `tests/health_spec.lua`
- A focused Herdr backend spec (new, or a clearly separated section in `tests/session_spec.lua`)
- `README.md`, `CONFIG.md`, `USAGE.md`, `ARCHITECTURE.md`, `DEVELOPMENT.md`, `CHANGELOG.md`, and `doc/ajans.nvim.txt` as affected

## Reuse

- Reuse the abstract session lifecycle in `lua/ajans/cli/session/init.lua`.
- Reuse stable tool/cwd session IDs through `Session.sid` and cwd normalization through `Session.cwd`.
- Reuse the existing terminal wrapper rather than creating a second Neovim window/buffer lifecycle; `herdr agent attach <terminal_id>` is compatible with the current terminal-job boundary.
- Reuse `Util.exec` for CLI execution and add a small Herdr JSON-response decoder local to the backend rather than introducing a raw socket protocol implementation.
- Reuse each tool’s `Tool:is_proc` matcher against Herdr `pane process-info` argv/cmdline data. Fast-path Herdr agent labels and Ajans-owned names, then inspect every remaining pane so externally started and custom configured tools have the same discovery coverage as tmux.
- Reuse the existing `tool.env` launch contract: pass string values with repeated Herdr `--env KEY=VALUE`; on Unix, preserve `false` (unset) values by prefixing launched argv with `env -u KEY` because Herdr’s launch API has no unset field.
- Reuse tmux behavior unchanged in `lua/ajans/cli/session/tmux.lua`.

## Steps

- [x] Confirm Herdr target (`ogulcancelik/herdr`) and full-parity requirement.
- [x] Inspect Herdr’s authoritative command/API behavior and map its core commands to Ajans’s session contract.
- [x] Define explicit backend configuration plus deterministic auto-detection, defaults, validation, and migration behavior.
- [x] Add Herdr `>= 0.7.0` version/capability validation and actionable errors.
- [x] Refactor backend registration/selection without changing tmux behavior.
- [x] Implement a Herdr CLI adapter that decodes JSON responses/errors, treats a stopped server as an empty discovery result, and starts `herdr server` detached with a bounded readiness wait only when creating the first session.
- [x] Implement full Herdr pane discovery using `api snapshot`, stable Ajans-owned agent names, Herdr agent-label aliases, and `pane process-info` for every unmatched pane; retain Herdr terminal/pane/workspace/tab IDs and process PIDs on session state.
- [x] Implement transactional Herdr creation for terminal/workspace, tab/window, and current-tab split placement, with direct argv/env launch, post-launch split sizing via `pane layout`/`pane resize`, and cleanup of temporary containers on partial failure.
- [x] Implement direct attach, literal send, Enter submission, liveness checks, and ANSI scrollback capture through `agent attach`, `agent send`, `pane send-keys`, `agent get`, and `pane read`.
- [x] Generalize terminal/state/UI integration where it currently assumes tmux, and de-duplicate an attached terminal wrapper from its backend parent by stable backend identity rather than tmux client PID overlap.
- [x] Update health checks and error reporting for the selected backend.
- [x] Add a table-driven parity contract test suite covering every capability above against both backend command adapters; do not consider the backend complete while any parity row is skipped or Herdr-only functionality is marked unsupported.
- [x] Update configuration, usage, architecture, help, and changelog documentation without documenting any degraded Herdr mode beyond the agreed platform/version prerequisites.

## Verification

- Run formatting and static checks documented in `DEVELOPMENT.md`.
- Run the full test suite plus focused session/config/health tests, including all-pane/custom-tool discovery, malformed/error Herdr JSON, stopped-server discovery, startup timeout, transactional rollback, fractional/cell split sizing, ordered multiline input, environment values/unsets, disappeared panes, persistent detach/reopen, and attached-parent de-duplication.
- Run the table-driven tmux/Herdr parity suite with zero skips and retain its matrix as the release gate.
- Manually verify creating, discovering, attaching, sending to, submitting to, hiding, reopening, and closing both Herdr and tmux sessions, including agents started outside Ajans.
- Verify behavior inside Herdr, inside tmux, and outside either multiplexer, including `terminal`, `window`/tab, and `split` creation paths where applicable.
- Verify explicit `tmux` and `herdr` selection plus the full auto-detection matrix (host environment, running Herdr server, one/both/neither installed).
- Verify a clear health/error path when no usable backend is available or Herdr is older than `0.7.0`.
- On macOS/Linux, manually verify direct Herdr terminal attachment. Windows support is explicitly out of scope for this iteration.
