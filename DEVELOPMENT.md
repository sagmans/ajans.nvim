# Development

Contributor notes for ajans.nvim.

## Repo layout

| Path | Purpose |
| --- | --- |
| `lua/ajans/config.lua` | Defaults, setup, validation, highlights. |
| `lua/ajans/commands.lua` | `:Ajans` command parser. |
| `lua/ajans/cli/init.lua` | Public CLI Lua API. |
| `lua/ajans/cli/actions.lua` | Built-in CLI terminal action handlers used by keymaps. |
| `lua/ajans/cli/session/` | Backend selection and tmux/Herdr session adapters. |
| `lua/ajans/cli/terminal.lua` | Neovim terminal wrapper. |
| `lua/ajans/cli/context/` | Prompt context providers. |
| `lua/ajans/cli/picker/` | snacks, Telescope, fzf-lua picker adapters. |
| `aj/cli/` | Bundled AI CLI tool configs. |
| `tests/` | mini.test suite. |
| `tests/fixtures/readme.lua` | Generated documentation snippets. |
| `lua/ajans/docs.lua` | Docs generation script. |
| `doc/ajans.nvim.txt` | Neovim help file for `:help ajans.nvim`; `.txt` is standard Vim helpdoc format. |

## Commands

```bash
./scripts/test
./scripts/docs
stylua lua tests
selene
```

Notes:

- `./scripts/test` runs the mini.test suite through `tests/minit.lua`.
- Set `LAZY_OFFLINE=1` when you need to avoid Lazy.nvim bootstrap downloads in offline environments.
- `./scripts/docs` regenerates marked blocks in `CONFIG.md`, `KEYMAPS.md`, and `USAGE.md`.

## Generated docs

Do not edit generated blocks directly. Update source, then run `./scripts/docs`.

`lua/ajans/docs.lua` maps generated snippets to split docs with `Docs.save(...)`:

- config reference -> `CONFIG.md`
- suggested user keymaps -> `KEYMAPS.md`
- CLI API, statusline, and picker examples -> `USAGE.md`

| Marker | Target file | Source |
| --- | --- | --- |
| `config` | `CONFIG.md` | `lua/ajans/config.lua` |
| `setup_base` | `KEYMAPS.md` | `tests/fixtures/readme.lua` |
| `api_cli` | `USAGE.md` | `lua/ajans/cli/init.lua` and `lua/ajans/commands.lua` |
| `snacks_picker` | `USAGE.md` | `tests/fixtures/readme.lua` |
| `setup_lualine` | `USAGE.md` | `tests/fixtures/readme.lua` |

## Session backend contract

Both backend adapters implement `start`, `attach`, `detach`, `sessions`, `send`, `submit`, `dump`, and `is_running`. Add behavior to the table-driven contract in `tests/mux_parity_spec.lua` when this interface changes. Herdr command tests must mock `_run`/`_run_many`; the ordinary test harness must not inspect or mutate a developer's live Herdr server. Real lifecycle harnesses are intentionally deferred to [Herdr issue #11](https://github.com/sagmans/ajans.nvim/issues/11) and [tmux issue #10](https://github.com/sagmans/ajans.nvim/issues/10); those harnesses must use isolated temporary namespaces and recorded-ID cleanup only.

## Adding a CLI tool

1. Add `aj/cli/{name}.lua`.
2. Add the tool key under `cli.tools` in `lua/ajans/config.lua`.
3. Include at least `cmd`, `is_proc`, and `url` when possible.
4. Add formatter/keymap/focus/scroll options only when the tool needs them.
5. Update tests if tool loading or formatting behavior changes.
6. Run `./scripts/docs` and `./scripts/test`.

## Adding config

1. Add the default in `lua/ajans/config.lua` with Lua annotations.
2. Add validation in `config.setup` when values are constrained.
3. Add/adjust tests in `tests/config_spec.lua`.
4. Document behavior in `CONFIG.md` outside generated block if users need guidance.
5. Run `./scripts/docs`.

## Adding context variables

1. Add provider in `lua/ajans/cli/context/init.lua` or via config docs if user-defined only.
2. Return `nil`/`false` when context is unavailable.
3. Add tests in `tests/context_spec.lua` or related specs.
4. Document user-facing behavior in `USAGE.md`.

## Adding keymaps

1. Add default terminal mappings in `lua/ajans/config.lua` only when broadly useful.
2. Implement action in `lua/ajans/cli/actions.lua` if it is not a terminal method or Ex command.
3. Cover behavior in terminal/keymap tests.
4. Update `KEYMAPS.md`.

## Validation checklist

Before shipping docs or behavior changes:

```bash
./scripts/docs
./scripts/test
stylua lua tests
```

Also check:

```bash
rg '<img|user-attachments' README.md *.md
rg 'README.md|CONFIG.md|KEYMAPS.md|USAGE.md|ARCHITECTURE.md|DEVELOPMENT.md' README.md *.md
```

Use `selene` when installed.
