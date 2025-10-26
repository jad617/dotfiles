------------------------------------------------------------
-- [[ Locals ]]
------------------------------------------------------------
local map = vim.api.nvim_set_keymap -- set keys
local options = { noremap = true, silent = true }

------------------------------------------------------------
-- [[ Zellij ]]
------------------------------------------------------------
-- Alt+o: Zellij floating terminal in Neovim's cwd, closes on Ctrl-D/exit
-- vim.keymap.set("n", "<A-o>", function()
--   local cwd = (vim.loop and vim.loop.cwd()) or vim.fn.getcwd()
--   local shell = os.getenv("SHELL") or "bash"
--   local cmd = string.format(
--     [[zellij run --floating --width 90%% --height 95%% --x 6%% --y 2%% --close-on-exit -- bash -lc 'cd %q && exec %q']],
--     cwd,
--     shell
--   )
--   vim.fn.jobstart(cmd, { detach = true })
-- end, { silent = true, desc = "Zellij float here (75%)" })
--
-- vim.keymap.set("n", "<D-o>", function()
--   local cwd = (vim.loop and vim.loop.cwd()) or vim.fn.getcwd()
--   local shell = os.getenv("SHELL") or "bash"
--   local cmd = string.format(
--     [[zellij run --floating --width 90%% --height 95%% --x 6%% --y 2%% --close-on-exit -- bash -lc 'cd %q && exec %q']],
--     cwd,
--     shell
--   )
--   vim.fn.jobstart(cmd, { detach = true })
-- end, { silent = true, desc = "Zellij float here (75%)" })

------------------------------------------------------------
-- [[ Select current word without jumping to next ]]
------------------------------------------------------------
-- Define a Lua function to search for the next occurrence of the word under the cursor
function Search_current_word()
  -- Save the current cursor position
  local saved_cursor_pos = vim.fn.getpos(".")

  -- Get the word under the cursor
  -- local current_word = vim.fn.expand("<cword>")

  -- Search for the word
  vim.cmd("normal! *")

  -- Restore the cursor position
  vim.fn.setpos(".", saved_cursor_pos)
end

-- Map the function to the desired key combination
vim.api.nvim_set_keymap("n", "<leader>8", "<cmd>lua Search_current_word()<CR>", options)

------------------------------------------------------------
-- [[ OpenNotesTelescope ]]
------------------------------------------------------------
-- Allows to open Telescope in our notes directory to open or create new notes
function OpenNotesTelescope()
  local root_dir = "~/notes"
  local full_path = vim.fn.expand(root_dir)
  if vim.fn.isdirectory(full_path) == 0 then
    vim.fn.mkdir(full_path, "p")
    os.execute("touch " .. full_path .. "/VERSION")
  end

  vim.api.nvim_set_current_dir(full_path)
  vim.cmd(":lua Snacks.picker.files({hidden = true})")
end

map("i", "<A-n>", "<C-c>:lua OpenNotesTelescope()<CR>", options)
map("n", "<A-n>", ":lua OpenNotesTelescope()<CR>", options)

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

map("n", "<D-f>", ":lua GitCommitAmendAndForcePush()<CR>", options)
map("i", "<D-f>", "<C-c>:lua GitCommitAmendAndForcePush()<CR>", options)

map("n", "<A-/>", ':lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)
map("i", "<A-/>", '<C-c>:lua GitCommitAndPush(vim.fn.input("Git Push commit message: "))<CR> ', options)

-- [[ Make ]]
map("n", "<A-'>", ":!make ", options)
map("i", "<A-'>", "<C-c>:!make ", options)
