-- Indent lines
return {
  "lukas-reineke/indent-blankline.nvim",
  enabled = true,
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
}
