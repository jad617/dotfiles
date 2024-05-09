return {
  "lewis6991/gitsigns.nvim",
  config = function()
    -- Add spacing for gitsigns
    vim.cmd("set signcolumn=yes")

    ------------------------------------------------------------
    -- [[ Setup ]]
    ------------------------------------------------------------
    require("gitsigns").setup({
      signs = {
        add = { hl = "GitSignsAdd", text = "│", numhl = "GitSignsAddNr", linehl = "GitSignsAddLn" },
        change = { hl = "GitSignsChange", text = "│", numhl = "GitSignsChangeNr", linehl = "GitSignsChangeLn" },
        delete = { hl = "GitSignsDelete", text = "_", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn" },
        topdelete = { hl = "GitSignsDelete", text = "‾", numhl = "GitSignsDeleteNr", linehl = "GitSignsDeleteLn" },
        changedelete = { hl = "GitSignsChange", text = "~", numhl = "GitSignsChangeNr", linehl = "GitSignsChangeLn" },
      },
      signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
      numhl = false, -- Toggle with `:Gitsigns toggle_numhl`
      linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
      word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
    })

    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local map = vim.api.nvim_set_keymap -- set keys
    local options = { noremap = true }
    
    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    map("n", "<A-a>", ":Gitsigns preview_hunk<CR>", options)
    map("i", "<A-a>", "<C-c>:Gitsigns preview_hunk<CR>", options)
    
    map("n", "<A-g>", ":Gitsigns diffthis<CR>", options)
    map("i", "<A-g>", "<C-c>:Gitsigns diffthis<CR>", options)
    
    map("n", "<A-d>", ":Gitsigns toggle_deleted<CR>", options)
    map("i", "<A-d>", "<C-c>:Gitsigns toggle_deleted<CR>", options)
    
    -- [[ MacOs ]]
    -- Alt + a
    map("n", "å", ":Gitsigns preview_hunk<CR>", options)
    map("i", "å", "<C-c>:Gitsigns preview_hunk<CR>", options)
    -- Alt + g
    map("n", "©", ":Gitsigns diffthis<CR>", options)
    map("i", "©", "<C-c>:Gitsigns diffthis<CR>", options)
    -- Alt + d
    map("n", "∂", ":Gitsigns toggle_deleted<CR>", options)
    map("i", "∂", "<C-c>:Gitsigns toggle_deleted<CR>", options)
  end,
}
