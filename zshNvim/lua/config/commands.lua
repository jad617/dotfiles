------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local linters = require("config.vars").linter
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true }

-- ------------------------------------------------------------
-- -- [[ Select current word without jumping to next ]]
-- ------------------------------------------------------------
-- Define a Lua function to search for the next occurrence of the word under the cursor
function search_current_word()
  -- Save the current cursor position
  local saved_cursor_pos = vim.fn.getpos(".")

  -- Get the word under the cursor
  local current_word = vim.fn.expand("<cword>")

  -- Search for the word
  vim.cmd("normal! *")

  -- Restore the cursor position
  vim.fn.setpos(".", saved_cursor_pos)
end

-- Map the function to the desired key combination
vim.api.nvim_set_keymap("n", "<leader>8", "<cmd>lua search_current_word()<CR>", { noremap = true, silent = true })

-- ------------------------------------------------------------
-- -- [[ MasonLinterInstall ]]
-- ------------------------------------------------------------
-- local linter_list = {}
--
-- -- Add linters.formatting to linter_list
-- for _, linter in ipairs(linters.formatting) do
--   table.insert(linter_list, linter)
-- end
--
-- -- Add linters.diagnostics to linter_list
-- for _, linter in ipairs(linters.diagnostics) do
--   -- Loop inside linter_list
--   for index, value in ipairs(linter_list) do
--     -- If linter.diagnostics has the same value as linter_list
--     -- remove this value
--     if linter == value then
--       table.remove(linter_list, index)
--     end
--   end
--   table.insert(linter_list, linter)
-- end
--
-- local list_to_install = table.concat(linter_list, " ")
-- local mansonLinterInstall = "MasonInstall " .. list_to_install
--
-- vim.api.nvim_create_user_command("MasonLinterInstall", mansonLinterInstall, {})
