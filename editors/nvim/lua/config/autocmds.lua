--- Autocmds are automatically loaded on the VeryLazy event
--- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--- Add any additional autocmds here

-- ------------------------------------------------------------
-- -- [[ Auto Open Workspace List ]]
-- ------------------------------------------------------------
-- https://github.com/AstroNvim/AstroNvim/issues/344#issuecomment-1214143220
vim.api.nvim_create_augroup("workspaces", {})
vim.api.nvim_create_autocmd("UiEnter", {
  desc = "Open workspaces automatically",
  group = "workspaces",
  callback = function()
    if vim.fn.argc() == 0 then vim.fn.execute("SnacksWorkspaces") end
  end,
})

------------------------------------------------------------
-- [[ Auto Open Snacks Explorer ]]
------------------------------------------------------------
vim.api.nvim_create_augroup("snacks_explorer", {})

-- Open the explorer whenever a real file buffer appears in a tab that
-- doesn't already have an explorer panel (covers: workspace selection,
-- nvim <file>, opening a file in a new tab).
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = "snacks_explorer",
  desc = "Auto-open explorer when a file buffer appears",
  callback = function(ev)
    local buf = ev.buf
    -- Only for real file buffers
    if vim.bo[buf].buftype ~= "" then return end
    if vim.api.nvim_buf_get_name(buf) == "" then return end
    -- Skip if explorer is already visible in this tab
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype:match("^snacks_") then return end
    end
    vim.schedule(function()
      Snacks.explorer()
      vim.defer_fn(function() vim.cmd("wincmd p") end, 50)
    end)
  end,
})

-- Quit neovim when the explorer is the only window left (close_if_last_window)
vim.api.nvim_create_autocmd("WinClosed", {
  group = "snacks_explorer",
  desc = "Quit nvim if only the snacks explorer remains",
  callback = function()
    vim.schedule(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) then
          local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
          if not ft:match("^snacks_") then return end
        end
      end
      vim.cmd("qa!")
    end)
  end,
})

------------------------------------------------------------
-- [[ Auto Reload if file changed ]]
------------------------------------------------------------
vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI", "FocusGained" }, {
  command = "if mode() != 'c' | checktime | endif",
  pattern = { "*" },
})

------------------------------------------------------------
-- Disable semanticTokensProvider
-- This messes up the syntax highlight colorscheme
------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    client.server_capabilities.semanticTokensProvider = nil
  end,
})

------------------------------------------------------------
-- Ansible file pattern
------------------------------------------------------------
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("Ansible", { clear = true }),
  pattern = {
    "*/roles/*/*/*.yaml",
    "*/roles/*/*/.yml",
    "*/inventory/*/group_vars/*",
    "*/inventory/*/host_vars/*",
    "main.yml",
    "main.yaml",
    "*/playbooks/*.yaml",
    "*/playbooks/*.yml",
    "group_vars/*.yml",
    "group_vars/*.yaml",
    "host_vars/*.yml",
    "host_vars/*.yaml",
    "files/*.yaml",
    "files/*.yml",
    "environments/*.yaml",
    "environments/*.yml,",
  },
  callback = function()
    vim.opt.filetype = "yaml.ansible"
    vim.cmd("TSDisable highlight")
  end,
})

------------------------------------------------------------
-- Fix terraform and hcl comment string
------------------------------------------------------------
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("FixTerraformCommentString", { clear = true }),
  callback = function(ev) vim.bo[ev.buf].commentstring = "# %s" end,
  pattern = { "terraform", "hcl" },
})

------------------------------------------------------------
-- Terminal: copy on select, easy exit from insert mode
------------------------------------------------------------
vim.api.nvim_create_augroup("terminal_settings", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
  group = "terminal_settings",
  callback = function(ev)
    local buf = ev.buf

    -- Large scroll buffer
    vim.opt_local.scrollback = 100000

    -- Scroll up/down while staying in terminal insert mode
    -- <C-\><C-o> executes one normal-mode command then returns to terminal insert mode
    vim.keymap.set("t", "<C-o>", "<C-\\><C-o><C-u>", { buffer = buf, noremap = true })
    vim.keymap.set("t", "<C-p>", "<C-\\><C-o><C-d>", { buffer = buf, noremap = true })

    -- Shift+Arrow in terminal mode navigates WezTerm panes directly.
    -- Bypasses smart-splits so we never accidentally focus a Neovim buffer
    -- from the floating terminal.
    local wez_dirs = { Left = "<S-Left>", Right = "<S-Right>", Up = "<S-Up>", Down = "<S-Down>" }
    for dir, key in pairs(wez_dirs) do
      vim.keymap.set("t", key, function()
        vim.fn.system("wezterm cli activate-pane-direction " .. dir)
      end, { buffer = buf, noremap = true, silent = true })
    end
  end,
})

-- Auto-enter insert mode whenever a terminal window is focused.
-- Covers re-toggling a hidden float (Snacks start_insert only fires on creation).
-- defer_fn(50ms) lets Snacks finish showing the float before we touch anything.
-- chansend("\x03") sends Ctrl+C which cancels any partial input and forces
-- zsh/bash to redraw a clean prompt at the correct column (fixes cursor drift).
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = "terminal_settings",
  callback = function()
    if vim.bo.buftype ~= "terminal" then return end
    vim.cmd("startinsert")
    local job_id = vim.b.terminal_job_id
    vim.defer_fn(function()
      if vim.bo.buftype ~= "terminal" then return end
      if job_id and job_id > 0 then vim.fn.chansend(job_id, "\x03") end
    end, 50)
  end,
})

-- Close terminal buffer silently on exit regardless of exit code.
-- Snacks' auto_close=false disables its built-in handler (which shows an
-- error notification on non-zero exit); this replaces it quietly.
vim.api.nvim_create_autocmd("TermClose", {
  group = "terminal_settings",
  callback = function(ev)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then vim.api.nvim_buf_delete(ev.buf, { force = true }) end
    end)
  end,
})

------------------------------------------------------------
-- highlight on yank
------------------------------------------------------------
vim.cmd([[
  augroup highlight_yank
  autocmd!
  au TextYankPost * silent! lua vim.highlight.on_yank({higroup="Visual", timeout=200})
  augroup END
]])
