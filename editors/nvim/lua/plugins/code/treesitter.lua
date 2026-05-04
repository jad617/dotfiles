-- nvim-treesitter (main branch) is now a pure parser + query manager for Neovim 0.12+.
-- Highlighting, indentation, and folding are handled natively by Neovim itself.
-- This config only manages parser installation.
return {
  "nvim-treesitter/nvim-treesitter",
  branch = "main",
  lazy = false, -- main branch does not support lazy loading
  build = ":TSUpdate",
  dependencies = {
    "windwp/nvim-ts-autotag",
  },
  config = function()
    require("nvim-treesitter").setup({
      install_dir = vim.fn.stdpath("data") .. "/site",
    })

    -- Parsers to keep installed. Neovim 0.12+ bundles: c, lua, vim, vimdoc, markdown, markdown_inline.
    -- All others are downloaded and compiled by nvim-treesitter.
    local ensure_installed = {
      "bash",
      "css",
      "diff",
      "dockerfile",
      "gitignore",
      "go",
      "gomod",
      "gosum",
      "hcl",
      "helm",
      "html",
      "javascript",
      "json",
      "lua",
      "make",
      "markdown",
      "markdown_inline",
      "python",
      "regex",
      "terraform",
      "tsx",
      "vim",
      "vimdoc",
      "yaml",
    }

    -- Auto-install any missing parsers on startup
    local installed = require("nvim-treesitter").get_installed()
    local installed_set = {}
    for _, lang in ipairs(installed) do
      installed_set[lang] = true
    end

    local missing = {}
    for _, lang in ipairs(ensure_installed) do
      if not installed_set[lang] then
        table.insert(missing, lang)
      end
    end

    if #missing > 0 then
      require("nvim-treesitter").install(missing)
    end

    -- autotag setup (uses native treesitter API, nvim-treesitter plugin is optional)
    require("nvim-ts-autotag").setup()
  end,
}
