return {
  "folke/noice.nvim",
  -- enabled = false,
  event = "VeryLazy",
  dependencies = {
    "MunifTanjim/nui.nvim",
    "rcarriga/nvim-notify",
  },
  config = function()
    require("noice").setup({
      messages = {
        enabled = false,
      },
      notify = {
        enabled = true,
      },
    })
  end,
}
