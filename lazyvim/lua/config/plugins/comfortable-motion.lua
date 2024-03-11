-- [[ local vars ]]
local cmd = vim.cmd -- cmd
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true, silent = true }

-- [[ Config ]]
cmd([[let g:comfortable_motion_no_default_key_mappings = 1]])
cmd([[let g:comfortable_motion_scroll_down_key = "j"]])
cmd([[let g:comfortable_motion_scroll_up_key = "k"]])
cmd([[let g:comfortable_motion_friction = 300.0]])
cmd([[let g:comfortable_motion_air_drag = 4.0]])

------------------------------------------------------------
-- [[ Key Bindings ]]
------------------------------------------------------------

-- [[ Default]]
map("n", "<C-o>", ":call comfortable_motion#flick(-100)<CR>", options)
map("i", "<C-o>", "<C-c>:call comfortable_motion#flick(-100)<CR>", options)

map("n", "<C-p>", ":call comfortable_motion#flick(100)<CR>", options)

-- TODO: need to find a way to force this behavior
map("i", "<C-p>", "<C-c>:call comfortable_motion#flick(100)<CR>", options)
