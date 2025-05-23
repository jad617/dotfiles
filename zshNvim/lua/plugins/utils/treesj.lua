return {
  "Wansmer/treesj",
  enabled = false,
  keys = { "<space>m", "<space>j", "<space>s" },
  dpendencies = { "nvim-treesitter/nvim-treesitter" }, -- if you install parsers with `nvim-treesitter`
  config = function()
    require("treesj").setup({})
  end,
}
