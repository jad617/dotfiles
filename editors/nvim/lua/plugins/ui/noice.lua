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
