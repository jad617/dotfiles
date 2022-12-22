--------------------------------------- [[ Packer Init ]]
local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath("data") .. "/site/pack/packer/start/packer.nvim"
  if fn.empty(fn.glob(install_path)) > 0 then
    fn.system({ "git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path })
    vim.cmd([[packadd packer.nvim]])
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

--------------------------------------- [[ Plugins ]]

return require("packer").startup(function(use)
  -- Packer
  use("wbthomason/packer.nvim")

  --------------------------------[ START ]------------------------------------

  ------------------------------------------------------------
  -- [[ Theme ]]
  ------------------------------------------------------------
  -- Onedark
  use("monsonjeremy/onedark.nvim")

  ------------------------------------------------------------
  -- [[ Utils ]]
  ------------------------------------------------------------
  -- Nvim-tree: nerdtree in lua
  use({
    "kyazdani42/nvim-tree.lua",
    requires = {
      "kyazdani42/nvim-web-devicons", -- optional, for file icons
    },
    tag = "nightly", -- optional, updated every week. (see issue #1193)
  })

  -- Telescope
  use({
    "nvim-telescope/telescope.nvim",
    tag = "0.1.0",
    requires = { { "nvim-lua/plenary.nvim" } },
  })

  -- Tab bar line
  -- use {
  --   'romgrk/barbar.nvim',
  --   requires = {'kyazdani42/nvim-web-devicons'}
  -- }

  -- Lualine: status line
  use({
    "nvim-lualine/lualine.nvim",
    requires = { "kyazdani42/nvim-web-devicons", opt = true },
  })

  use("beauwilliams/statusline.lua") -- Statusline, is used for tabline feature only

  -- Add Comments
  use("tpope/vim-commentary")
  use("dstein64/vim-startuptime")

  -- Tmux Split navigator
  use("christoomey/vim-tmux-navigator")

  -- Vim run command in Tmux split
  use('preservim/vimux')

  -- Smooth Scrolling
  -- use 'karb94/neoscroll.nvim'
  -- use 'psliwka/vim-smoothie'
  use("yuttie/comfortable-motion.vim")

  -- View Indents
  use("lukas-reineke/indent-blankline.nvim")

  -- Remove Whitespaces
  use("ntpeters/vim-better-whitespace")

  -- Auto pairs
  use("windwp/nvim-autopairs")

  -- Git
  use("lewis6991/gitsigns.nvim")

  -- Markdown
  use({
    "iamcco/markdown-preview.nvim",
    run = function()
      vim.fn["mkdp#util#install"]()
    end,
  })

  -- Jenkins
  use({
    'ckipp01/nvim-jenkinsfile-linter',
    requires = { "nvim-lua/plenary.nvim" }
  })

  ------------------------------------------------------------
  -- [[ IDE ]]
  ------------------------------------------------------------
  -- LSP
  -- use({ "fatih/vim-go" })
  use({ "williamboman/mason.nvim" }) -- LSP/Linter installer
  use({ "williamboman/mason-lspconfig.nvim" }) -- Mason config
  use({ "neovim/nvim-lspconfig" }) -- Configurations for Nvim LSP
  use({ "jose-elias-alvarez/null-ls.nvim" })

  use({ "L3MON4D3/LuaSnip", tag = "v<CurrentMajor>.*" })

  -- Muli Language Syntax
  use({ "nvim-treesitter/nvim-treesitter" })
  -- use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }

  -- GoToDefinition in floating window
  use ('rmagatti/goto-preview')

  -- Rename word on cursor
  use ({
    "smjonas/inc-rename.nvim",
    requires = {
      'stevearc/dressing.nvim',
    },
  })

  -- LSP Autocomplete
  use({
    "hrsh7th/nvim-cmp",
    requires = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "saadparwaiz1/cmp_luasnip",
      "hrsh7th/cmp-nvim-lua",
      "ray-x/cmp-treesitter",
      -- "hrsh7th/cmp-calc",
      -- "f3fora/cmp-spell",
      "hrsh7th/cmp-emoji",
      -- "rafamadriz/friendly-snippets",
      disable = false,
    },
  })

  -- Add icons to cmp
  use("onsails/lspkind.nvim")

  -- Terraform Syntaxt
  use({
    "hashivim/vim-terraform",
    ft = {'terraform'},
  })

  -- -- Auto tag treesitter html
  use({
    "windwp/nvim-ts-autotag",
    wants = "nvim-treesitter",
    event = "InsertEnter",
    config = function()
      require("nvim-ts-autotag").setup({ enable = true })
    end,
  })

  -- -- End wise
  use({
    "RRethy/nvim-treesitter-endwise",
    wants = "nvim-treesitter",
  })

  ----------------------------------[ END ]------------------------------------

  -- Automatically set up your configuration after cloning packer.nvim
  -- Put this at the end after all plugins
  if packer_bootstrap then
    require("packer").sync()
  end
end)
