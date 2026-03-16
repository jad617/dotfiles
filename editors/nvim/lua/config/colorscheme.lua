------------------------------------------------------------
-- [[ Load colorscheme ]]
------------------------------------------------------------
vim.cmd.colorscheme("onedark")
-- vim.cmd.colorscheme("tokyonight-storm")
-- vim.cmd.colorscheme("catppuccin-macchiato")

------------------------------------------------------------
-- [[ Custom Overrides ]]
------------------------------------------------------------

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight GitSignsAdd guifg=#9ECE6A guibg=NONE")

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight GitSignsAdd guifg=#9ECE6A guibg=NONE")

-- Snacks borders color
vim.cmd("highlight SnacksPickerBoxBorder   guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerListBorder  guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerInputBorder guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerPreviewBorder guifg=#ff9e64 guibg=NONE")

-- Explorer-specific highlights (dark bg, explicit so no transparent inheritance)
vim.cmd("highlight ExplorerNormal      guibg=#1a1f2b guifg=NONE")
vim.cmd("highlight ExplorerBorder      guifg=#ff9e64 guibg=#1a1f2b")
vim.cmd("highlight ExplorerSeparator   guifg=#c27fd7 guibg=#1a1f2b")

-- Cursor color of the searched word
vim.cmd("highlight SnacksPickerPreviewCursorLine guibg=#61afef guifg=#282c34 gui=bold")

-- Search box background color (regular pickers)
vim.cmd("highlight SnacksPicker     guibg=#242b38")
vim.cmd("highlight SnacksPickerBox  guibg=#242b38")
vim.cmd("highlight SnacksPickerInput guibg=#242b38")
vim.cmd("highlight SnacksPickerList guibg=#242b38 gui=bold")
vim.cmd("highlight SnacksPickerPreview guibg=#242b38 gui=bold")

vim.cmd("highlight SnacksExplorerSeparator guifg=#c27fd7 guibg=NONE gui=bold")

-- Snacks picker title color
vim.cmd("highlight SnacksPickerPreviewTitle guifg=#c27fd7 gui=bold")
vim.cmd("highlight SnacksPickerBoxTitle guifg=#c27fd7 gui=bold")
-- Explorer uses SnacksPickerListCursorLine when focused, CursorLine when unfocused
vim.cmd("highlight CursorLine guibg=#98C379 guifg=#282c34 gui=bold")
vim.cmd("highlight SnacksPickerListCursorLine guibg=#5a8f42 guifg=#e8e8e8 gui=bold")

-- Snacks terminal color
vim.cmd("highlight FloatBorder guifg=#9ECE6A gui=bold")

-- Cursor color
vim.cmd("highlight NvimCursorGreen guifg=#282c34 guibg=#98C379 gui=bold ctermfg=235 ctermbg=114 cterm=bold")
vim.cmd("highlight Cursor guifg=#282c34 guibg=#98C379 gui=bold")
vim.cmd("highlight lCursor guifg=#282c34 guibg=#98C379 gui=bold")
vim.cmd("highlight TermCursor guifg=#282c34 guibg=#98C379 gui=bold")
vim.cmd("highlight TermCursorNC guifg=#282c34 guibg=#98C379 gui=bold")
vim.cmd("highlight nCursor guifg=#282c34 guibg=#98C379 gui=bold")
vim.opt.guicursor = "n-v-c:block-NvimCursorGreen,i-ci-ve:ver25-NvimCursorGreen,r-cr:hor20-NvimCursorGreen,o:hor50-NvimCursorGreen,a:blinkon0"
