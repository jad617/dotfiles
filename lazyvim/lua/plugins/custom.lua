-- stylua: ignore

return {
  ------------------------------------------------------------
  -- [[ Themes ]]
  ------------------------------------------------------------
  -- Onedark
  -- { "monsonjeremy/onedark.nvim", name = "onedark", priority = 1000 },

  { "navarasu/onedark.nvim", name = "onedark", priority = 1000 },

  -- Everblush
  { "Alexis12119/nightly.nvim" },

  { 'Everblush/nvim', name = 'everblush' },

  -- Onedark Pro
  -- { "olimorris/onedarkpro.nvim", priority = 1000 },

  -- Kanagawa
  { "rebelot/kanagawa.nvim", name = "kanagawa", priority = 1000 },

  -- Catppuccin
  { "catppuccin/nvim", name = "catppuccin", priority = 1000 },

  -- OneNord
  { "rmehri01/onenord.nvim", name = "onenord", priority = 1000 },

  -- Nordic
  { "AlexvZyl/nordic.nvim", name = "nordic", priority = 1000 },

  { 'glepnir/zephyr-nvim',
    requires = { 'nvim-treesitter/nvim-treesitter', opt = true },
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

  -- Helm
  { 'towolf/vim-helm' },

  -- Mustace tpl
  { "mustache/vim-mustache-handlebars" },



  -- Terraform Syntaxt
  -- {
  --   "hashivim/vim-terraform",
  --   ft = {'terraform'},
  -- },
  --
  ------------------------------------------------------------
  -- [[ Utils ]]
  ------------------------------------------------------------

  -- Colorizer
  { "NvChad/nvim-colorizer.lua",
    config = function()
      require('colorizer').setup {}
    end,
  },

  -- color windows
  -- {
  -- "nvim-zh/colorful-winsep.nvim", config = true, event = { "WinNew" },
  -- },

  -- html auto reload
  {
    'barrett-ruth/live-server.nvim',
    build = {
      'sudo npm install -g live-server',
      'sudo yarn global add live-server'
    },
    config = true,
  },

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
  -- {
  --   "christoomey/vim-tmux-navigator",
  --   lazy = false,
  -- },
  --

  -- Terminal float
  { "numToStr/FTerm.nvim" },
  -- Tmux split run command
  { 'preservim/vimux' },

  -- Window resizer
  { "anuvyklack/windows.nvim",
    dependencies = {
        "anuvyklack/middleclass",
        "anuvyklack/animation.nvim"
    },
    config = function()
       vim.o.winwidth = 10
       vim.o.winminwidth = 10
       vim.o.equalalways = false
       require('windows').setup()
    end
  },

  -- Window picker works with neo-tree
  {
    's1n7ax/nvim-window-picker',
    name = 'window-picker',
    event = 'VeryLazy',
    version = '2.*',
    config = function()
        require'window-picker'.setup({
        selection_chars = 'ABDCEFG',
      })
    end,
  },



  -- Vim Screenshot
  -- Install CMAKE + Cargo
  -- https://cmake.org/install/
  -- {
  --   'segeljakt/vim-silicon',
  --   build = {
  --     'cargo install silicon'
  --   },
  -- },
}
