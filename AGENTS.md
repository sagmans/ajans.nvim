# Agent Cheat Sheet

This repository contains `ajans.nvim`, a Neovim plugin that provides an integrated terminal workflow for AI CLI tools.

## Project Overview

- Core modules live under `lua/ajans/` (`config.lua`, `cli/`, `status.lua`, etc.).
- Tests are written with `mini.test` and live in `tests/`. Specs are table-driven whenever possible.
- `tests/helpers/test.lua` is the typed bridge to MiniTest's collection-time BDD globals and Luassert; specs import its locals instead of declaring test globals.
- Reference docs are generated automatically via `./scripts/docs`, which updates marked blocks in `CONFIG.md`, `KEYMAPS.md`, and `USAGE.md`.
- Code style is Lua with `stylua` / `selene` configs already included.

## Everyday Commands

- `./scripts/test` – runs the `mini.test` suite using the Lazy.nvim harness; automatically installs test dependencies. Set `LAZY_OFFLINE=1` when you need to skip the bootstrap download (for fully offline CI).
- `./scripts/docs` – regenerates marked docs blocks from `lua/ajans/config.lua`, `lua/ajans/cli/init.lua`, and `tests/fixtures/readme.lua`.
- `stylua lua tests aj` – format Lua source, tests, and bundled tool configs when needed.
- `selene` – lint Lua files (if selene is installed in the environment).
- Inspect Neovim help topics from the CLI:

  ```bash
  nvim --headless \
    '+lua vim.cmd.help("nvim_buf_set_extmark"); print(table.concat(vim.api.nvim_buf_get_lines(0, vim.fn.line(".") - 1, vim.fn.line(".") + 50, false), "\n"))' +qa
  ```

  Swap in the topic/API you need to research.

## Adding Features

- Keep new configuration options documented in `lua/ajans/config.lua`; docs are generated from this file.
- If a change affects CLI session status reporting, extend `tests/status_spec.lua` so notifications stay covered.
- If a change affects context collection, extend the corresponding spec in `tests/`.

## Writing Tests

- Import `assert`, BDD functions, and hooks from `tests.helpers.test`; keep the adapter surface limited to APIs the suite uses.
- Use `mini.test` assertions (`assert.are.same`, `assert.is_true`, etc.).
- Prefer table-driven specs for combinatorial cases.
- Type deliberately partial fixtures at their test-owned seams instead of weakening production contracts or inflating fixtures.
- Stub Neovim APIs carefully: reassign functions and restore them in `after_each` hooks. For upvalue-based helpers (e.g., health reporters), use `debug.setupvalue`.

## Things to Watch

- The repo may run in headless CI where network calls are blocked; stubs or fixtures should avoid third-party fetches.
- Avoid touching generated docs directly—run `./scripts/docs` instead.
- Maintain ASCII unless the surrounding context already uses Unicode (icons in configs are fine).

## Useful Paths

- CLI orchestration: `lua/ajans/cli/init.lua`
- CLI actions: `lua/ajans/cli/actions.lua`
- CLI sessions: `lua/ajans/cli/session/init.lua`
- Herdr integration advice: `lua/ajans/cli/session/herdr/integrations.lua`
- Status integration: `lua/ajans/status.lua`
- Tests entry point: `tests/minit.lua`

Keep this sheet handy when automating changes or onboarding new agents.
