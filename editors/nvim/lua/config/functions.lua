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
  local command = "git add -A && git commit -m " .. vim.fn.shellescape(commit_message) .. " && git push"
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

-- [[ LSP commands (native Neovim 0.12+ replacements for nvim-lspconfig commands) ]]
vim.api.nvim_create_user_command("LspStop", function()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    client:stop()
    vim.notify("LSP stopped: " .. client.name, vim.log.levels.INFO)
  end
end, { desc = "Stop all LSP clients attached to current buffer" })

vim.api.nvim_create_user_command("LspStart", function()
  vim.api.nvim_exec_autocmds("FileType", {
    group = "nvim.lsp.enable",
    buffer = 0,
  })
end, { desc = "Start LSP for current buffer" })

vim.api.nvim_create_user_command("LspRestart", function()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = client.name
    client:stop()
  end
  vim.defer_fn(function()
    for _, name in ipairs(names) do
      vim.lsp.enable(name)
    end
    vim.api.nvim_exec_autocmds("FileType", {
      group = "nvim.lsp.enable",
      buffer = 0,
    })
  end, 500)
end, { desc = "Restart all LSP clients attached to current buffer" })

vim.api.nvim_create_user_command("LspInfo", function()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify("No LSP clients attached to this buffer", vim.log.levels.WARN)
    return
  end
  local lines = { "LSP clients for: " .. vim.fn.expand("%:~:."), "" }
  for _, client in ipairs(clients) do
    lines[#lines + 1] = "  ● " .. client.name .. " (id=" .. client.id .. ")"
    lines[#lines + 1] = "    root : " .. (client.root_dir or "—")
    lines[#lines + 1] = "    cmd  : " .. table.concat(client.config.cmd or {}, " ")
    lines[#lines + 1] = "    pid  : " .. tostring(client.rpc and client.rpc.pid or "—")
    lines[#lines + 1] = ""
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.diagnostic.enable(false, { bufnr = buf })
  local width = math.min(70, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " LSP Info ",
    title_pos = "center",
  })
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = close,
  })
end, { desc = "Show LSP client info for current buffer" })

-- [[ Go: fetch new dependencies and restart gopls ]]
-- Use <leader>gG inside any Go buffer to run `go get ./...` + `go mod tidy`
-- asynchronously, then restart gopls so it picks up the new packages.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "go",
  group = vim.api.nvim_create_augroup("GoGetDeps", { clear = true }),
  callback = function(ev)
    vim.keymap.set("n", "<leader>gG", function()
      local root = vim.fs.root(ev.buf, { "go.mod", "go.work", ".git" }) or vim.fn.getcwd()
      vim.cmd("noautocmd silent! write") -- bypass goimports so unused imports stay on disk
      vim.notify("go get ./... && go mod tidy — running…", vim.log.levels.INFO)
      vim.fn.jobstart({ "sh", "-c", "go get ./... && go mod tidy" }, {
        cwd = root,
        on_exit = function(_, code)
          if code == 0 then
            vim.notify("go get done — restarting gopls…", vim.log.levels.INFO)
            vim.schedule(function()
              for _, client in ipairs(vim.lsp.get_clients({ name = "gopls" })) do
                client:stop()
              end
              vim.defer_fn(function()
                vim.lsp.enable("gopls")
                vim.api.nvim_exec_autocmds("FileType", {
                  group = "nvim.lsp.enable",
                  buffer = ev.buf,
                })
                vim.notify("gopls restarted — wait a moment for indexing", vim.log.levels.INFO)
              end, 500)
            end)
          else
            vim.notify("go get failed (exit " .. code .. ")", vim.log.levels.ERROR)
          end
        end,
      })
    end, { buffer = ev.buf, desc = "Go: get deps + restart gopls" })
  end,
})
