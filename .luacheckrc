-- luacheck configuration, read by scripts/lint (pre-commit and pre-push).
-- Why: luacheck catches dead stores, unused values, shadowing and undefined
-- globals that stylua (layout) and selene do not reject. Every rule relaxed
-- below states why, so a later change can tell intent from accident.

-- Neovim embeds LuaJIT, so plugin code may use Lua 5.1 plus LuaJIT globals
-- (jit, bit) and nothing newer.
std = "luajit"

-- Writable, not read-only: specs stub Neovim APIs by reassigning fields of
-- `vim` (see AGENTS.md, "Stub Neovim APIs carefully").
globals = { "vim" }

-- Optional runtime global set by snacks.nvim; the plugin only reads it.
read_globals = { "Snacks" }

-- Session backends, the terminal wrapper and their test doubles share one
-- colon-method interface; base stubs and simple backends ignore their state,
-- and dropping `self` would break the `obj:method()` call contract.
self = false

-- stylua (stylua.toml, column_width = 120) owns line layout. The lines it
-- leaves long are user-facing message strings and LuaLS annotations that it
-- cannot wrap; splitting them would hurt grep and annotation parsing.
max_line_length = false

-- Untracked trees that test runs and local experiments create (see
-- .gitignore): third-party plugin code there is not this project's to lint.
exclude_files = {
  ".tests/**",
  ".repro/**",
  "build/**",
  "debug/**",
  "node_modules/**",
  ".antigravitycli/**",
}
