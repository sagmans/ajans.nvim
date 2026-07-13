#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
vim.env.LAZY_PATH = vim.fs.normalize("~/projects/lazy.nvim")

if vim.fn.isdirectory(vim.env.LAZY_PATH) == 1 then
  loadfile(vim.env.LAZY_PATH .. "/bootstrap.lua")()
else
  load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"), "bootstrap.lua")()
end

-- Setup lazy.nvim
require("lazy.minit").setup({
  spec = {
    {
      dir = vim.uv.cwd(),
      opts = { cli = { mux = { backend = "tmux" } } },
    },
    { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
    { "folke/snacks.nvim" },
    {
      "nvim-treesitter/nvim-treesitter",
      branch = "main",
      build = ":TSUpdate",
      config = function()
        local TS = require("nvim-treesitter")
        TS.setup({})
        TS.install({ "python", "rust", "javascript", "typescript", "go", "lua" }, { summary = true }):wait()
      end,
    },
  },
})

-- Tests must never inspect or mutate the developer's live Herdr session.
require("ajans.cli.session.herdr")._run = function(cmd)
  if cmd[2] == "status" then
    return {
      code = 0,
      stdout = '{"status":"not_running","running":false}\n',
      stderr = "",
    }
  end
  return {
    code = 1,
    stdout = "",
    stderr = "failed to connect to Herdr server: test command execution is mocked\n",
  }
end

-- TODO: check why this is needed
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
