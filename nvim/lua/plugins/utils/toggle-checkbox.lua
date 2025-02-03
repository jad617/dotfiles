return {
  enabled = false,
  "opdavies/toggle-checkbox.nvim",
  config = function()
    local map = vim.api.nvim_set_keymap -- set keys
    map("n", "<leader>tt", ":lua require('toggle-checkbox').toggle()<CR>", { noremap = true, silent = true })
    map("n", "<leader>b", ":lua require('toggle-checkbox').toggle()<CR>", { noremap = true, silent = true })
  end,
}
