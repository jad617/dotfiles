return {
  enabled = false,
  "numToStr/FTerm.nvim",
  config = function()
    require("FTerm").setup({
      border = "double",
      dimensions = {
        height = 1.0,
        width = 0.9,
        x = 0.8,
        y = 0.5,
      },
    })

    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local map = vim.api.nvim_set_keymap -- set keys
    local options_silent = { noremap = true, silent = true }

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    -- map("n", "<c-/>", ':lua require("FTerm").toggle()<CR>', options_silent)
    -- vim.keymap.set("n", "<A-i>", '<CMD>lua require("FTerm").toggle()<CR>')
    vim.keymap.set("n", "<A-i>", '<CMD>lua require("FTerm").open()<CR>')
    vim.keymap.set("t", "<A-i>", '<C-\\><C-n><CMD>lua require("FTerm").close()<CR>')
  end,
}
