require("config.options")

local enable_config = require("config.global_functions").FileNotTooBig()
if enable_config then
  require("config.lazy")
  require("config.autocmds")
  require("config.keymaps")
  require("config.functions")
  require("config.colorscheme")
end

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight GitSignsAdd guifg=#9ECE6A guibg=NONE")

-- Change highlight color for plugin GitSigns
vim.cmd("highlight GitSignsChange guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight GitSignsAdd guifg=#9ECE6A guibg=NONE")

-- Snacks borders color
vim.cmd("highlight SnacksPickerBoxBorder guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerListBorder guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerInputBorder guifg=#ff9e64 guibg=NONE")
vim.cmd("highlight SnacksPickerPreviewBorder guifg=#ff9e64 guibg=NONE")

-- Cursor color of the searched word
vim.cmd("highlight SnacksPickerPreviewCursorLine guibg=#61afef guifg=#282c34 gui=bold")

-- Search box background color
vim.cmd("highlight SnacksPickerList guibg=#242b38 gui=bold")
vim.cmd("highlight SnacksPickerPreview guibg=#242b38 gui=bold")

-- Snacks picker title color
vim.cmd("highlight SnacksPickerPreviewTitle guifg=#c27fd7 gui=bold")
vim.cmd("highlight SnacksPickerBoxTitle guifg=#c27fd7 gui=bold")
