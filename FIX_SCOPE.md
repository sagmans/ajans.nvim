# LuaLS diagnostic remediation scope — Ajans

Status: approved design; implementation pending.

## Goal

Repair Ajans-owned LuaLS contracts without weakening runtime types, changing Herdr security behavior, or compensating in source for missing external metadata.

`./scripts/test` passed before remediation: **374 cases, 0 failures**. The diagnostics are static-analysis debt, not a reproduced runtime failure.

## Dependency boundary

BUM must provide version-appropriate Neovim, Luv, and Snacks metadata before Ajans diagnostics are considered authoritative. A fresh baseline produced **1,515 diagnostics across 47 files** with BUM's current LuaLS configuration. A temporary source-only configuration with Neovim, Luv, and Snacks libraries reduced that to **80 diagnostics across 14 files**.

External metadata remains outside this change:

- Neovim runtime types, including `vim.SystemCompleted`, keysets, quickfix entries, and Tree-sitter classes.
- Luv handle and spawn-option types.
- Snacks picker types.
- MiniTest/Luassert test-framework globals and assertions.
- Neovim 0.13 development metadata that conflicts with Ajans's Neovim 0.11.2 compatibility surface.

## Approved design

Use localized contract repair. Types remain beside their owning modules; no central type registry and no blanket conversion of required production fields to optional fields.

- Shared session lifecycle and authorization state belongs to the common session class.
- Herdr-only liveness and queued-operation state belongs to the Herdr class.
- Backend-specific capabilities use narrow interfaces instead of leaking full concrete classes.
- Discovery receives an explicit static adapter rather than the Herdr instance prototype.
- Constructor inputs, helper inputs, discovered state, and initialized instances remain distinct contracts.
- Runtime behavior remains unchanged except where an existing return annotation is observably false or Lua accidentally returns an extra value.

## Ajans-owned remediation scope

| Area | Evidence | Required repair |
| --- | --- | --- |
| Position aliases | `ajans.Pos` is referenced by context, scrollback, and `Util.fix_pos`, but never declared | Define one namespaced two-integer `(row, col)` tuple alias near common text/location types |
| Textobject range | `Range6` is referenced only by `get_textobject_range()` | Define a namespaced six-integer Tree-sitter range alias beside the textobject module |
| Callback docs | `config.lua` documents `terminal` for `_terminal`; base `Session:send()` documents `text` for `_text` | Align annotation names with implementation parameters |
| Picker interface | `cli/picker/init.lua` declares `P.action(): fun()` but its interface stub returns nothing | Express picker methods as type-only fields rather than executable empty methods |
| Process matching | Built-in command matching reads a subset of `Proc`, while user callbacks may consume the full inventory type | Introduce a narrow built-in match-evidence type without weakening the configured callback's full `Proc` contract |
| Session model | Session creation, discovered state, initialized instances, Herdr identity metadata, `fresh`, and shared authorization/input fields are conflated | Define truthful creation/state/interface fields and retain required initialized fields |
| Narrow helper interfaces | `Scrollback.is_enabled()` and terminal parent authorization use only small subsets of full classes | Type each helper against the capability it consumes; do not inflate test doubles |
| Herdr prototype state | Herdr writes liveness and queued-operation fields without declarations | Declare backend-owned fields and operation shapes on Herdr |
| Herdr discovery seam | `DiscoveryBackend` rejects the Herdr prototype | Pass one explicit adapter implementing request, snapshot support, and batch execution |
| Return contracts | Herdr `_spawn()`, `attach()`, and `start()` annotations disagree with actual branches; state attachment can return `nil`; discovery exposes `gsub()`'s count | Correct unions, normalize promised booleans, parenthesize single-value returns, and make final outcomes explicit |
| Flow narrowing | Send callbacks, optional `ps_command()`, validated layouts, optional inventories, and Herdr client parameters remain wider than their guarded runtime state | Add guards, local types, or post-validation casts at the owning seam |
| Shared backend metadata | Session reconciliation reads Herdr identity fields and writes backend/authorization state absent from common contracts | Declare optional discovery metadata and shared state where reconciliation owns it |
| Compatibility-only options | Detached Herdr startup passes ignored `vim.system` options that conflict with current metadata | Stop passing options to the dedicated server-spawn adapter; preserve detached spawn behavior in `Client.spawn_server()` |

## Explicit non-goals

- Do not change BUM configuration in this work.
- Do not add repository MiniTest/Luassert metadata.
- Do not add required production fields to test doubles merely to silence `missing-fields`.
- Do not make required initialized class fields globally optional.
- Do not blanket-disable diagnostics or add broad casts.
- Do not hard-code local Neovim, LuaLS, dependency, or `.tests` paths in Ajans.
- Do not alter Herdr process authorization, socket trust, payload transport, environment isolation, or lifecycle behavior.
- Do not replace `vim.keymap.set()`'s Neovim 0.11-compatible option solely for Neovim 0.13 development metadata.

## Implementation order

1. Add behavior-focused failing tests for normalized attachment booleans and single-value discovery errors.
2. Repair common aliases, session state, constructor inputs, and narrow helper interfaces.
3. Repair process matching and picker interfaces.
4. Repair Herdr state, discovery adapter, return contracts, and flow narrowing.
5. Re-run LuaLS with external source metadata and classify every remaining source diagnostic.
6. Run tests, formatter, Selene workaround, generated-doc check, and diff checks.

## Verification

- `./scripts/test`
- `stylua --check lua tests`
- LuaLS source diagnostics with temporary Neovim/Luv/Snacks metadata; no Ajans-owned residuals
- remediation-scope Selene validation
- `./scripts/docs` with no generated drift
- `git diff --check`
