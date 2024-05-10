------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true, silent = true }

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
vim.api.nvim_set_keymap("n", "<leader>8", "<cmd>lua search_current_word()<CR>", options)

-- ------------------------------------------------------------
-- -- [[ Open Notes ]]
-- ------------------------------------------------------------

function open_notes()
  local dir = "/home/jelasmar/notes"
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  vim.cmd("cd " .. dir)
  vim.cmd("tabnew")
end
