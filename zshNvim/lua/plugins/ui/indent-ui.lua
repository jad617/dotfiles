return {
  -- Indent lines
  "lukas-reineke/indent-blankline.nvim",
  enabled = false,
  main = "ibl",
  opts = {
    indent = {
      char = "│",
      tab_char = "│",
    },
    scope = { enabled = false },
    whitespace = { highlight = { "Whitespace", "NonText" } },
    exclude = {
      filetypes = {
        "help",
        "alpha",
        "dashboard",
        "neo-tree",
        "Trouble",
        "trouble",
        "lazy",
        "mason",
        "notify",
        "toggleterm",
        "lazyterm",
        "terminal",
      },
    },
  },

  -- Indent lines animation
  {
    "echasnovski/mini.indentscope",
    enabled = false,
    config = function()
      require("mini.indentscope").setup({
        options = {
          try_as_border = true,
        },
        symbol = "│",
      })
    end,
  },
}
