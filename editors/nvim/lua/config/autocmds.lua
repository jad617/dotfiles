--- Autocmds are automatically loaded on the VeryLazy event
--- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--- Add any additional autocmds here

-- ------------------------------------------------------------
-- -- [[ Auto Open Workspace List ]]
-- ------------------------------------------------------------
-- https://github.com/AstroNvim/AstroNvim/issues/344#issuecomment-1214143220
vim.api.nvim_create_augroup("workspaces", { clear = true })
vim.api.nvim_create_autocmd("UiEnter", {
  desc = "Open workspaces automatically",
  group = "workspaces",
  callback = function()
    if vim.fn.argc() == 0 then vim.fn.execute("SnacksWorkspaces") end
  end,
})

------------------------------------------------------------
-- [[ Auto Open Neotree ]]
------------------------------------------------------------
-- https://github.com/AstroNvim/AstroNvim/issues/344#issuecomment-1214143220
vim.api.nvim_create_augroup("neotree", { clear = true })
vim.api.nvim_create_autocmd("UiEnter", {
  desc = "Open Neotree automatically",
  group = "neotree",
  callback = function()
    if vim.fn.argc() > 0 then
      vim.cmd("Neotree action=show toggle=true dir=")
      vim.cmd("Neotree action=show toggle=true dir=")
    end
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
local function is_shell_terminal(buf_name)
  for _, shell in ipairs({ "zsh", "bash", "sh", "fish" }) do
    if buf_name:match(shell .. "$") then return true end
  end
  return false
end
vim.api.nvim_create_autocmd("TermOpen", {
  group = "terminal_settings",
  callback = function(ev)
    local buf = ev.buf

    -- Large scroll buffer
    vim.opt_local.scrollback = 100000

    -- ESC exits terminal insert mode → normal mode.
    -- Double-press is not needed; single ESC is enough since AI CLIs
    -- (claude, gh copilot) operate at the shell/prompt level.
    vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { buffer = buf, noremap = true, silent = true })

    -- Scroll up/down while staying in terminal insert mode (shell terminals only).
    -- <C-\><C-o> executes one normal-mode command then returns to terminal insert mode.
    -- Excluded from AI CLI terminals (e.g. sidekick_terminal) because:
    --   1. <C-p> is sidekick's built-in "insert prompt" binding — overriding it breaks it.
    --   2. The brief normal-mode <C-\><C-o> hop can leave the buffer in normal mode if a
    --      WinEnter autocmd fires during it, making <Space> silently swallowed as leader.
    local buf_name = vim.api.nvim_buf_get_name(buf)
    if is_shell_terminal(buf_name) then
      vim.keymap.set("t", "<C-o>", "<C-\\><C-o><C-u>", { buffer = buf, noremap = true })
      vim.keymap.set("t", "<C-p>", "<C-\\><C-o><C-d>", { buffer = buf, noremap = true })
    end

    -- Shift+Arrow in terminal mode:
    -- • floating terminal → skip smart-splits (it would land on the buffer
    --   behind the float) and jump directly to the WezTerm pane instead.
    -- • regular terminal split → use smart-splits as normal.
    local ss_dirs = {
      ["<S-Left>"]  = { ss = "move_cursor_left",  wez = "Left"  },
      ["<S-Right>"] = { ss = "move_cursor_right", wez = "Right" },
      ["<S-Up>"]    = { ss = "move_cursor_up",    wez = "Up"    },
      ["<S-Down>"]  = { ss = "move_cursor_down",  wez = "Down"  },
    }
    for key, dirs in pairs(ss_dirs) do
      vim.keymap.set("t", key, function()
        local cfg = vim.api.nvim_win_get_config(0)
        if cfg.relative ~= "" then
          -- floating window: go straight to WezTerm, ignore Neovim splits
          vim.fn.jobstart({ "wezterm", "cli", "activate-pane-direction", dirs.wez }, { detach = true })
        else
          require("smart-splits")[dirs.ss]()
        end
      end, { buffer = buf, noremap = true, silent = true })
    end
  end,
})

-- When FocusGained re-focuses the float via nvim_set_current_win it triggers
-- WinEnter. jobresize in WinEnter is only needed for Snacks toggles (new
-- window); in the FocusGained path the cursor is already at ┗❯ and jobresize
-- would send a spurious SIGWINCH that scrambles ZLE → gibberish output.
local _refocusing_from_wezterm = false

-- Auto-enter insert mode whenever a terminal window is focused.
-- Covers re-toggling a hidden float (Snacks start_insert only fires on creation).
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
  group = "terminal_settings",
  callback = function()
    if vim.bo.buftype ~= "terminal" then return end
    -- vim.schedule ensures startinsert fires after all synchronous WinEnter
    -- handlers, including sidekick's which calls stopinsert() when restoring
    -- a previously-saved normal mode. Without this, sidekick wins the race
    -- and leaves the buffer in normal mode — where <Space> is swallowed as
    -- the leader key and never reaches the terminal process.
    vim.schedule(function()
      if vim.bo.buftype ~= "terminal" then return end
      local cfg = vim.api.nvim_win_get_config(0)
      if cfg.relative ~= "" then
        -- Scroll the window to the last buffer line so the prompt is visible
        -- immediately (Snacks creates a new window on each show() which may
        -- start scrolled to the top).
        local last = vim.api.nvim_buf_line_count(0)
        vim.api.nvim_win_set_cursor(0, { last, 0 })

        -- oh-my-posh right-aligned segments leave VTerm's cursor on the ┏━
        -- line after rendering, so startinsert alone puts input there instead
        -- of ┗❯. jobresize() sends SIGWINCH to the process group (unlike
        -- kill -WINCH which only hits the shell PID), which forces ZLE to
        -- fully redraw the prompt — cursor ends up on ┗❯ where it belongs.
        -- Skip when coming from FocusGained: cursor is already correct there,
        -- and an extra SIGWINCH scrambles ZLE → gibberish in the prompt.
        if not _refocusing_from_wezterm then
          local job_id = vim.b.terminal_job_id
          if job_id and job_id > 0 then
            local win = vim.api.nvim_get_current_win()
            local w = vim.api.nvim_win_get_width(win)
            local h = vim.api.nvim_win_get_height(win)
            vim.fn.jobresize(job_id, w, h + 1)
            vim.defer_fn(function()
              if vim.api.nvim_win_is_valid(win) then
                vim.fn.jobresize(job_id, w, h)
              end
            end, 100)
          end
        end
      end
      vim.cmd("startinsert")
    end)
  end,
})

-- When Neovim regains focus (e.g. switching back from another WezTerm pane),
-- if a floating terminal is visible, jump to it so it stays in the foreground.
vim.api.nvim_create_autocmd("FocusGained", {
  group = "terminal_settings",
  callback = function()
    vim.schedule(function()
      local cur_win = vim.api.nvim_get_current_win()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
          local cfg = vim.api.nvim_win_get_config(win)
          local buf = vim.api.nvim_win_get_buf(win)
          if cfg.relative ~= "" and vim.bo[buf].buftype == "terminal" then
            if win ~= cur_win then
              -- Float is not the active window: switch to it.
              -- WinEnter handler takes care of startinsert.
              _refocusing_from_wezterm = true
              vim.api.nvim_set_current_win(win)
              vim.defer_fn(function() _refocusing_from_wezterm = false end, 10)
            else
              -- Float IS already current: just ensure we're in terminal mode.
              if vim.fn.mode() ~= "t" then vim.cmd("startinsert") end
            end
            return
          end
        end
      end
    end)
  end,
})

-- When a WezTerm split is created/closed, the Neovim pane resizes →
-- VimResized fires → Neovim auto-jobresize sends SIGWINCH to ZSH, which
-- corrupts VTerm's cursor state (oh-my-posh right-aligned segments leave the
-- VTerm cursor on the ┏━ line). No SIGWINCH trick or Ctrl-L can fix an
-- already-corrupted VTerm. Instead, replicate the Snacks toggle (hide+show):
-- hide() destroys the window/VTerm, show() creates a fresh one, and the
-- WinEnter jobresize(h+1→h) then fixes oh-my-posh cursor position — the
-- exact same sequence that works when the user manually toggles off/on.
-- 400ms delay gives oh-my-posh time to finish its auto-jobresize render
-- before we do the hide, so the hide+show starts from a stable ZSH state.
vim.api.nvim_create_autocmd("VimResized", {
  group = "terminal_settings",
  callback = function()
    vim.schedule(function()
      local ok, snacks = pcall(require, "snacks")
      if not ok then return end
      for _, term in ipairs(snacks.terminal.list()) do
        if term:valid() then
          term:hide()
          vim.defer_fn(function()
            if not term:valid() then term:show() end
          end, 400)
          return
        end
      end
    end)
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

-- DEBUG: :WinInfo — prints all window info
vim.api.nvim_create_user_command("WinInfo", function()
  local lines = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) then
      local buf = vim.api.nvim_win_get_buf(w)
      local cfg = vim.api.nvim_win_get_config(w)
      local pos = vim.api.nvim_win_get_position(w)
      table.insert(lines, string.format(
        "win=%d ft=%-25s bt=%-8s w=%-4d col=%-4d float=%s name=%s",
        w, vim.bo[buf].filetype, vim.bo[buf].buftype,
        vim.api.nvim_win_get_width(w), pos[2],
        tostring(cfg.relative ~= ""),
        vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
      ))
    end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, {})
