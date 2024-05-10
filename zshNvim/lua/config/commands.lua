------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true, silent = true }

------------------------------------------------------------
-- [[ Select current word without jumping to next ]]
------------------------------------------------------------
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

------------------------------------------------------------
-- [[ Open Notes ]]
------------------------------------------------------------
-- function open_notes(filename)
--   if not (filename == "") then
--     local dir = "/home/jelasmar/notes"
--     if vim.fn.isdirectory(dir) == 0 then
--       vim.fn.mkdir(dir, "p")
--     end
--     vim.cmd("tabnew " .. dir .. "/" .. filename)
--     require("neo-tree.command").execute({ action = "show", toggle = true, dir = dir })
--   end
-- end
function open_notes(filename)
  if not (filename == "") then
    local root_dir = "/home/jelasmar/notes"
    local dir = root_dir

    -- Split the filename into directory and file components
    local path_separator = "/"
    local subdirs = {}
    local file = filename

    -- If filename contains '/'
    if filename:find(path_separator) then
      subdirs = vim.split(filename, path_separator, true) -- Split the filename by '/'
      file = subdirs[#subdirs] -- Get the last component as the filename
      table.remove(subdirs) -- Remove the last component from the list (the filename itself)
    end

    -- Create subdirectories if they don't exist
    for _, subdir in ipairs(subdirs) do
      dir = dir .. "/" .. subdir:gsub("%s+", "")
      if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
      end
    end

    -- Open the file in the appropriate directory
    vim.cmd("tabnew " .. dir .. "/" .. file)

    -- Show directory tree
    require("neo-tree.command").execute({ action = "show", toggle = true, dir = root_dir })
  end
end

map("i", "<A-n>", '<C-c>:lua open_notes(vim.fn.input("Note file to open:"))<CR> ', options)
map("n", "<A-n>", ':lua open_notes(vim.fn.input("Note file to open:"))<CR> ', options)

------------------------------------------------------------
-- [[ Git ]]
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

map("n", "<A-f>", ":lua GitCommitAmendAndForcePush()<CR>", options)
map("i", "<A-f>", "<C-c>:lua GitCommitAmendAndForcePush()<CR>", options)

map("n", "<A-/>", ':lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)
map("i", "<A-/>", '<C-c>:lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)

-- [[ Make ]]
map("n", "<A-'>", ":!make ", options)
map("i", "<A-'>", "<C-c>:!make ", options)
