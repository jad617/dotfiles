return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    enabled = false,
    priority = 1000,
  },
  {
    "sainnhe/gruvbox-material",
    enabled = false,
    priority = 1000,
    config = function()
      vim.g.gruvbox_material_transparent_background = 1
      vim.g.gruvbox_material_foreground = "mix"
      vim.g.gruvbox_material_background = "hard"
      vim.g.gruvbox_material_ui_contrast = "high"
      vim.g.gruvbox_material_float_style = "bright"
      vim.g.gruvbox_material_statusline_style = "material"
      vim.g.gruvbox_material_cursor = "auto"
      vim.cmd.colorscheme("gruvbox-material")
    end,
  },
  {
    "navarasu/onedark.nvim",
    enabled = true,
    name = "onedark",
    priority = 1000,
    config = function()
      require("onedark").setup({
        -- main
        -- style = "dark",
        -- style = "darker",
        -- style = "deep",
        style = "cool",

        toggle_style_key = "<leader>cs", -- keybind to toggle theme style. Leave it nil to disable it, or set it to a string, for example "<leader>ts"
        toggle_style_list = { "darker", "cool", "deep" }, -- List of styles to toggle between

        -- Change code style ---
        -- Options are italic, bold, underline, none
        -- You can configure multiple style with comma separated, For e.g., keywords = 'italic,bold'
        code_style = {
          comments = "italic",
          keywords = "bold",
          functions = "bold",
          strings = "none",
          variables = "bold",
        },

        -- Custom Highlights --
        colors = {
          bright_orange = "#ff9950", -- define a new color
          pastel_green = "#99bc80",
        }, -- Override default colors
        highlights = {

          -- ["@keyword"] = { fg = "$pastel_green" },

          ["@string"] = { fg = "$pastel_green", fmt = "bold" },
          -- [ Indent line ]
          MiniIndentscopeSymbol = { fg = "#ff8050" },
          -- [ NeoTree ]
          NeoTreeIndentMarker = { fg = "#ff8050" },
          NeoTreeWinSeparator = { fg = "#c27fd7" },
          NeoTreeNormal = { fg = "#99bc80", fmt = "bold" },
          NeoTreeNormalNC = { fg = "#99bc80", fmt = "bold" },
          -- NeoTreeRootName = { fg = "#e16d77" },
          -- [ LSP ]
          ["@module"] = { fg = "#ff4d94" },
          ["@operator"] = { fg = "#e16d77", fmt = "bold" },
          ["@variable.member.terraform"] = { fg = "#e16d71", fmt = "bold" },
          ["@variable.member.hcl"] = { fg = "#e16d71", fmt = "bold" },
          ["@variable.builtin.terraform"] = { fg = "#61afef" },
          ["@function.terraform"] = { fg = "#c27fd7" },
          ["@variable"] = { fg = "#ffa666" },
          ["@number"] = { fg = "#23a0a0" },
          ["@boolean"] = { fg = "#c27fd7" },
          ["@type.builtin"] = { fg = "#5fafb9" },
          ["@constant.builtin"] = { fg = "#ff4d94" },
          -- ["@variable.member"] = { fg = "#61afef", fmt = "bold" },
          -- [ Telescope ]
          TelescopePromptBorder = { fg = "#ff8050" },
          TelescopeResultsBorder = { fg = "#ff8050" },
          TelescopePreviewBorder = { fg = "#ff8050" },
        }, -- Override highlight groups
      })
    end,
  },
}
