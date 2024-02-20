-- [[ local vars ]]
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

-- [[ Setup ]]
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
-- [[ Key Bindings ]]
------------------------------------------------------------
function GitCommitAndPush(commit_message)
  local command = 'git add -A && git commit -m "' .. commit_message .. '" && git push'
  vim.fn.system(command)
end

function GitCommitAmendAndForcePush()
  local confirm = vim.fn.input("Are you sure you want to amend the last commit and force push? (y/n): ")
  if confirm == "y" then
    local command = "git add . && git commit --amend --no-edit && git push -f"
    print("Force Push Done")
    vim.fn.system(command)
  else
    print("Force Push Canceled")
  end
end

-- [[ Linux ]]

map("n", "<A-f>", ":lua GitCommitAmendAndForcePush()<CR>", options)
map("i", "<A-f>", "<C-c>:lua GitCommitAmendAndForcePush()<CR>", options)
map("i", "<A-f>", "<C-c>:!git add . && git commit --amend --no-edit && git push -f<CR>", options)
-- map("n", "<A-f>", ":!git add . && git commit --amend --no-edit && git push -f<CR>", options)
-- map("i", "<A-f>", "<C-c>:!git add . && git commit --amend --no-edit && git push -f<CR>", options)

map("n", "<A-/>", ':lua GitCommitAndPush(vim.fn.input("Commit message: "))<CR> ', options)
map("i", "<A-/>", '<C-c>:lua GitCommitAndPush(vim.fn.input("Commit message: "))<CR> ', options)

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
