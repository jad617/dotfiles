require("FTerm").setup({
  border = "double",
  dimensions = {
    height = 0.9,
    width = 0.4,
    x = 0.8,
    -- y = 0.7,
  },
})

-- Example keybindings
-- vim.keymap.set("n", "<c-/>", '<CMD>lua require("FTerm").toggle()<CR>')
-- vim.keymap.set("i", "<c-/>", '<C-\\><C-n><CMD>lua require("FTerm").toggle()<CR>')
-- vim.keymap.set("t", "<c-/>", '<C-\\><C-n><CMD>lua require("FTerm").toggle()<CR>')
