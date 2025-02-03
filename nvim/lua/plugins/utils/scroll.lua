return {
  "karb94/neoscroll.nvim",
  enabled = false,
  config = function()
    require("neoscroll").setup({
      mappings = {},
    })

    -- [[ Keymaps ]]
    local map = vim.api.nvim_set_keymap -- set keys
    local options = { noremap = true, silent = true }

    neoscroll = require("neoscroll")

    map("n", "<C-o>", ":lua neoscroll.ctrl_u()", options)

    map("n", "<C-p>", ":lua neoscroll.ctrl_u()", options)
  end,
}
