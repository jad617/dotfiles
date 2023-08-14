-- stylua: ignore

return {
  -- comfortable-motion
  { "yuttie/comfortable-motion.vim", enabled = true },

  -- Rename word on cursor
  {
    "smjonas/inc-rename.nvim",
    requires = {
      'stevearc/dressing.nvim',
    },
  },

  -- Markdown
  {
    "iamcco/markdown-preview.nvim",
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },

  -- Nvim-tree: nerdtree in lua
  {
    "kyazdani42/nvim-tree.lua",
    requires = {
      "kyazdani42/nvim-web-devicons", -- optional, for file icons
    },
    tag = "nightly", -- optional, updated every week. (see issue #1193)
  },

  -- Statusline
  { "beauwilliams/statusline.lua" }, -- Statusline, is used for tabline feature only

  -- Tmux Split navigator
  { "christoomey/vim-tmux-navigator" },

}
