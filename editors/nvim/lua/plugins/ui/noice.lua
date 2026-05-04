return {
  "folke/noice.nvim",
  enabled = true,
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  config = function()
    require("noice").setup({
      cmdline = {
        format = {
          -- disable treesitter highlighting for cmdline (vim query incompatible with Neovim 0.12.2 bundled parser)
          cmdline = { pattern = "^:", icon = "", lang = "" },
          search_down = { kind = "search", pattern = "^/", icon = " ", lang = "" },
          search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "" },
        },
      },
      messages = {
        enabled = true,
      },
      notify = {
        enabled = true,
      },
      routes = {
        -- Suppress benign ClaudeCode WebSocket disconnect on terminal close
        {
          filter = {
            event = "notify",
            find = "ECONNRESET",
          },
          opts = { skip = true },
        },
      },
    })
  end,
}
