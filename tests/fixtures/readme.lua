local base = {
  "sagmans/ajans.nvim",
  opts = {
    -- add any options here
  },
  -- stylua: ignore
  keys = {
    {
      "<c-.>",
      function() require("ajans.cli").focus() end,
      desc = "Ajans Focus",
      mode = { "n", "t", "i", "x" },
    },
    {
      "<leader>aa",
      function() require("ajans.cli").toggle() end,
      desc = "Ajans Toggle CLI",
    },
    {
      "<leader>as",
      function() require("ajans.cli").select() end,
      -- Or to select only installed tools:
      -- require("ajans.cli").select({ filter = { installed = true } })
      desc = "Select CLI",
    },
    {
      "<leader>ad",
      function() require("ajans.cli").close() end,
      desc = "Detach a CLI Session",
    },
    {
      "<leader>at",
      function() require("ajans.cli").send({ msg = "{this}" }) end,
      mode = { "x", "n" },
      desc = "Send This",
    },
    {
      "<leader>af",
      function() require("ajans.cli").send({ msg = "{file}" }) end,
      desc = "Send File",
    },
    {
      "<leader>av",
      function() require("ajans.cli").send({ msg = "{selection}" }) end,
      mode = { "x" },
      desc = "Send Visual Selection",
    },
    {
      "<leader>ap",
      function() require("ajans.cli").prompt() end,
      mode = { "n", "x" },
      desc = "Ajans Select Prompt",
    },
    -- Example of a keybinding to open Claude directly
    {
      "<leader>ac",
      function() require("ajans.cli").toggle({ name = "claude", focus = true }) end,
      desc = "Ajans Toggle Claude",
    },
  },
}

local lualine = {
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

local snacks_picker = {
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
