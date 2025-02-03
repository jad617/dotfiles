-- Tmux split run command
return {
  enabled = false,
  "preservim/vimux",
  config = function()
    ------------------------------------------------------------
    -- [[ local vars ]]
    ------------------------------------------------------------
    local map = vim.api.nvim_set_keymap -- set keys
    local options = { noremap = true, silent = true }

    ------------------------------------------------------------
    -- [[ Key Bindings ]]
    ------------------------------------------------------------
    -- [[ Linux ]]
    map("n", "<A-7>", ":VimuxRunCommand('python3 ' . bufname('%'))<CR>", options)
    map("n", "<A-8>", ":VimuxRunCommand('go run .')<CR>", options)

    map("n", "<A-9>", ":VimuxRunLastCommand<CR>", options)
    map("n", "<A-0>", ":VimuxPromptCommand<CR>", options)

    -- [[ MacOs ]]
    --noremap ƒ :VimuxRunLastCommand<CR>
    --noremap ∂ :VimuxPromptCommand<CR>
    -- local nvim_tmux_nav = require("nvim-tmux-navigation")
  end,
}
