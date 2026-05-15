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
          -- lang="" is truthy in Lua and still invokes Syntax.highlight() via nvim_buf_call,
          -- which interferes with ext_cmdline in Neovim 0.12 and drops the % range specifier.
          -- lang=false is falsy: it skips the highlight branch entirely and keeps % working.
          cmdline    = { pattern = "^:", icon = "", lang = false },
          search_down = { kind = "search", pattern = "^/",  icon = " ", lang = false },
          search_up   = { kind = "search", pattern = "^%?", icon = " ", lang = false },
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
