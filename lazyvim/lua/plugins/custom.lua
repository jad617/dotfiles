-- stylua: ignore

return {
  ------------------------------------------------------------
  -- [[ Themes ]]
  ------------------------------------------------------------
  -- Onedark
  {
    "monsonjeremy/onedark.nvim",
    name = "onedark",
    priority = 1000,
  },

  ------------------------------------------------------------
  -- [[ Languages ]]
  ------------------------------------------------------------
  -- Markdown
  {
    "iamcco/markdown-preview.nvim",
    build = function()
      vim.fn["mkdp#util#install"]()
    end,
  },

  -- Terraform Syntaxt
  {
    "hashivim/vim-terraform",
    ft = {'terraform'},
  },

  ------------------------------------------------------------
  -- [[ Utils ]]
  ------------------------------------------------------------

  -- Colorizer
  { "norcalli/nvim-colorizer.lua", enabled = true },

  -- comfortable-motion
  { "yuttie/comfortable-motion.vim", enabled = true },

  -- Indent
  {
    'nmac427/guess-indent.nvim',
    config = function()
      require('guess-indent').setup {}
    end,
  },

  -- Rename word on cursor
  {
    "smjonas/inc-rename.nvim",
    requires = {
      'stevearc/dressing.nvim',
    },
  },

  -- Nvim-tree: nerdtree in lua
  {
    "nvim-tree/nvim-tree.lua",
    version = "*",
    lazy = false,
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("nvim-tree").setup {}
    end,
  },

  -- Statusline, is used for tabline feature only
  { "beauwilliams/statusline.lua" },

  -- Tmux Split navigator
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
}
