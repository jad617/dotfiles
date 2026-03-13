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
-- [[ Auto Open Snacks Explorer ]]
------------------------------------------------------------
vim.api.nvim_create_augroup("snacks_explorer", { clear = true })

local EXPLORER_WIDTH = 30 -- fixed sidebar width in columns
local win_expand_layout
local rebalance_two_wins
local apply_window_layout

local WIN_ACTIVE_RATIO = 0.50
local WIN_ACTIVE_MIN_WIDTH = 80
local WIN_MIN_WIDTH = 10
local WIN_RESIZE_MIN_COLUMNS = 80
local WIN_ANIM_STEPS = 10
local WIN_ANIM_MS = 150
local needs_initial_file_sync = vim.fn.argc() == 0

local function get_explorer_picker()
  local snacks = rawget(_G, "Snacks")
  if type(snacks) ~= "table" or type(snacks.picker) ~= "table" then return nil end
  if type(snacks.picker.get) ~= "function" then return nil end

  local ok, pickers = pcall(snacks.picker.get, { source = "explorer" })
  if not ok or type(pickers) ~= "table" then return nil end
  return pickers[1]
end

local function get_current_tab_explorer_picker()
  local picker = get_explorer_picker()
  if not picker or picker.closed then return nil end
  if type(picker.on_current_tab) == "function" then
    local ok, on_current_tab = pcall(picker.on_current_tab, picker)
    if not ok or not on_current_tab then return nil end
  end
  return picker
end

local function canon_path(path)
  if not path or path == "" then return "" end
  -- Keep path style aligned with picker cwd (avoid realpath symlink expansion),
  -- otherwise explorer may add internal parent directories repeatedly.
  return vim.fs.normalize(path)
end

-- Resize the explorer's root split window directly.
-- Snacks reads root.win width as source of truth for split layouts (layout.lua:447-450),
-- so resizing it is the only reliable way to control sidebar width.
-- winfixwidth prevents neovim from auto-adjusting root when normal windows resize.
-- Exposed globally so snacks.lua <C-n> keymap can call it too.
local function fix_explorer_width()
  local picker = get_explorer_picker()
  if not picker then return false end
  local layout = picker.layout
  if not (layout and layout.root) then return false end
  local root_win = layout.root.win
  if vim.api.nvim_win_is_valid(root_win) then
    vim.wo[root_win].winfixwidth = true
    local snacks = rawget(_G, "Snacks")
    if type(snacks) == "table" and type(snacks.util) == "table" and type(snacks.util.winhl) == "function" then
      local merged = snacks.util.winhl(vim.wo[root_win].winhighlight, {
        WinSeparator = "SnacksExplorerSeparator",
      })
      if type(snacks.util.wo) == "function" then
        snacks.util.wo(root_win, { winhighlight = merged })
      end
    else
      local winhl = vim.wo[root_win].winhighlight or ""
      if winhl:match("WinSeparator:") then
        winhl = winhl:gsub("WinSeparator:[^,]*", "WinSeparator:SnacksExplorerSeparator")
      else
        winhl = (winhl == "" and "" or (winhl .. ",")) .. "WinSeparator:SnacksExplorerSeparator"
      end
      vim.wo[root_win].winhighlight = winhl
    end
    if vim.api.nvim_win_get_width(root_win) ~= EXPLORER_WIDTH then
      vim.api.nvim_win_set_width(root_win, EXPLORER_WIDTH)
    end
    return true
  end
  return false
end
_G.fix_explorer_width = fix_explorer_width

local function fix_explorer_current_file_highlight()
  local picker = get_current_tab_explorer_picker() or get_explorer_picker()
  if not (picker and picker.list and picker.list.win) then return false end

  local list_win = picker.list.win.win
  if not (list_win and vim.api.nvim_win_is_valid(list_win)) then return false end

  vim.wo[list_win].cursorline = true

  local snacks = rawget(_G, "Snacks")
  if type(snacks) == "table" and type(snacks.util) == "table" and type(snacks.util.winhl) == "function" then
    local merged = snacks.util.winhl(vim.wo[list_win].winhighlight, {
      CursorLine = "SnacksPickerListCursorLine",
    })
    if type(snacks.util.wo) == "function" then
      snacks.util.wo(list_win, { winhighlight = merged })
      return true
    end
  end

  local winhl = vim.wo[list_win].winhighlight or ""
  if winhl:match("CursorLine:") then
    winhl = winhl:gsub("CursorLine:[^,]*", "CursorLine:SnacksPickerListCursorLine")
  else
    winhl = (winhl == "" and "" or (winhl .. ",")) .. "CursorLine:SnacksPickerListCursorLine"
  end
  vim.wo[list_win].winhighlight = winhl
  return true
end

local function sync_explorer_file(file, picker)
  if not file or file == "" then return false end
  file = canon_path(file)
  picker = picker or get_current_tab_explorer_picker() or get_explorer_picker()
  if not picker or picker.closed then return false end

  if type(picker.iter) == "function" and picker.list and type(picker.list.view) == "function" then
    for item, idx in picker:iter() do
      if item and item.file and canon_path(item.file) == file then
        pcall(picker.list.view, picker.list, idx)
        return true
      end
    end
  end

  if type(picker.current) == "function" then
    local ok_current, item = pcall(picker.current, picker)
    if ok_current and item and item.file and canon_path(item.file) == file then
      return true
    end
  end

  local ok_actions, actions = pcall(require, "snacks.explorer.actions")
  if ok_actions and type(actions.reveal) == "function" then
    local ok_reveal, revealed = pcall(actions.reveal, picker, file)
    if ok_reveal and revealed then
      return true
    end
  end

  local snacks = rawget(_G, "Snacks")
  if type(snacks) == "table" and type(snacks.explorer) == "table" and type(snacks.explorer.reveal) == "function" then
    pcall(snacks.explorer.reveal, { file = file })
  end
  if type(picker.current) == "function" then
    local ok_current, item = pcall(picker.current, picker)
    if ok_current and item and item.file and canon_path(item.file) == file then
      return true
    end
  end
  return false
end

local function sync_explorer_to_current_buffer()
  local picker = get_current_tab_explorer_picker()
  if not picker then return false end

  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return false end
  local file = vim.api.nvim_buf_get_name(buf)
  return sync_explorer_file(file, picker)
end

local function apply_layout_retry(attempts_left)
  local layout_ok = type(apply_window_layout) == "function" and apply_window_layout()
  if layout_ok then
    return
  end
  if attempts_left > 0 then
    vim.defer_fn(function() apply_layout_retry(attempts_left - 1) end, 40)
  end
end

local function apply_explorer_style_retry(attempts_left)
  if attempts_left <= 0 then return end
  local sep_ok = fix_explorer_width()
  local hl_ok = fix_explorer_current_file_highlight()
  if sep_ok and hl_ok then return end
  vim.defer_fn(function() apply_explorer_style_retry(attempts_left - 1) end, 120)
end

local function sync_startup_buf_retry(buf, attempts_left, picker_ref)
  if attempts_left <= 0 then return end
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  if vim.bo[buf].buftype ~= "" then return end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return end

  local picker
  if type(picker_ref) == "function" then
    local ok, p = pcall(picker_ref)
    if ok then picker = p end
  end
  local synced = sync_explorer_file(file, picker)
  fix_explorer_current_file_highlight()
  if synced then return end
  vim.defer_fn(function() sync_startup_buf_retry(buf, attempts_left - 1, picker_ref) end, 200)
end

-- Open the explorer whenever a real file buffer appears in a tab that
-- doesn't already have an explorer panel (covers: workspace selection,
-- nvim <file>, opening a file in a new tab).
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = "snacks_explorer",
  desc = "Auto-open explorer when a file buffer appears",
  -- Needed so `wincmd p` inside this autocmd can trigger WinEnter,
  -- which applies win_expand_layout() on startup as well.
  nested = true,
  callback = function(ev)
    local buf = ev.buf
    -- Only for real file buffers
    if vim.bo[buf].buftype ~= "" then return end
    local file = vim.api.nvim_buf_get_name(buf)
    if file == "" then return end
    local startup_buf = buf
    if needs_initial_file_sync then needs_initial_file_sync = false end
    local current_tab_picker = get_current_tab_explorer_picker()
    if current_tab_picker then
      local picker_ref = type(current_tab_picker.ref) == "function" and current_tab_picker:ref() or nil
      vim.defer_fn(function()
        local synced = sync_explorer_file(vim.api.nvim_buf_get_name(startup_buf), current_tab_picker)
        fix_explorer_current_file_highlight()
        apply_explorer_style_retry(6)
        if not synced then
          sync_startup_buf_retry(startup_buf, 8, picker_ref)
        end
      end, 40)
      return
    end
    vim.schedule(function()
      Snacks.explorer({
        on_show = function(picker)
          local picker_ref = type(picker.ref) == "function" and picker:ref() or nil
          vim.defer_fn(function()
            local synced = sync_explorer_file(vim.api.nvim_buf_get_name(startup_buf), picker)
            fix_explorer_current_file_highlight()
            apply_explorer_style_retry(6)
            if not synced then
              sync_startup_buf_retry(startup_buf, 8, picker_ref)
            end
          end, 40)
        end,
      })
      vim.defer_fn(function()
        vim.cmd("wincmd p")
        apply_layout_retry(25)
        apply_explorer_style_retry(6)
      end, 80)
    end)
  end,
})

-- Quit neovim when the explorer is the only window left (close_if_last_window)
vim.api.nvim_create_autocmd("WinClosed", {
  group = "snacks_explorer",
  desc = "Quit nvim if only the snacks explorer remains",
  callback = function(ev)
    -- If a float closed (e.g. workspace picker), a file is about to open — don't quit yet
    local win_id = tonumber(ev.match)
    if win_id then
      local ok, config = pcall(vim.api.nvim_win_get_config, win_id)
      if ok and config.relative ~= "" then return end
    end
    vim.schedule(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(w) then
          local buf = vim.api.nvim_win_get_buf(w)
          -- A real file window: normal buftype with an actual file path
          if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then return end
        end
      end
      vim.cmd("qa!")
    end)
  end,
})

------------------------------------------------------------
-- [[ Auto-expand active buffer (replaces windows.nvim) ]]
------------------------------------------------------------
-- Returns only non-float, non-snacks windows.
-- Uses EXPLORER_WIDTH as the fixed left offset so the calculation is stable
-- regardless of neovim's actual explorer window state at call time.
local function get_normal_wins()
  local normal = {}
  local has_explorer = false
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) then
      if vim.api.nvim_win_get_config(w).relative ~= "" then goto continue end
      local ft = vim.bo[vim.api.nvim_win_get_buf(w)].filetype
      if ft:match("^snacks_") then
        has_explorer = true
      else
        table.insert(normal, w)
      end
    end
    ::continue::
  end
  -- +1 for the divider between explorer and buffers
  local min_col = has_explorer and (EXPLORER_WIDTH + 1) or 0
  return normal, min_col
end

rebalance_two_wins = function(normal, min_col)
  if #normal ~= 2 then return false end

  local available = vim.o.columns - min_col - 1 -- one divider between two windows
  if available < (2 * WIN_MIN_WIDTH) then return false end

  local equal_target = math.floor(available / 2)
  local needs_resize = false
  for _, w in ipairs(normal) do
    local current_w = vim.api.nvim_win_get_width(w)
    if math.abs(current_w - equal_target) > 1 then
      needs_resize = true
      break
    end
  end
  if not needs_resize then return true end

  for _, w in ipairs(normal) do
    if vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_set_width(w, equal_target)
    end
  end
  return true
end

win_expand_layout = function(normal, min_col)
  local active = vim.api.nvim_get_current_win()
  normal = normal or get_normal_wins()
  min_col = min_col or 0

  if #normal <= 2 then return end
  if vim.o.columns < WIN_RESIZE_MIN_COLUMNS then return end

  -- available = space to the right of the explorer, minus dividers between normal wins
  local available = vim.o.columns - min_col - (#normal - 1)
  local min_required = WIN_ACTIVE_MIN_WIDTH + ((#normal - 1) * WIN_MIN_WIDTH)
  if available < min_required then return end

  local max_active = available - ((#normal - 1) * WIN_MIN_WIDTH)
  local active_target = math.max(math.floor(available * WIN_ACTIVE_RATIO), WIN_ACTIVE_MIN_WIDTH)
  active_target = math.min(active_target, max_active)
  local rest_target = math.max(math.floor((available - active_target) / (#normal - 1)), WIN_MIN_WIDTH)

  local targets = {}
  local has_active = false
  local needs_resize = false
  for _, w in ipairs(normal) do
    if w == active then has_active = true end
    local target_w = (w == active) and active_target or rest_target
    local current_w = vim.api.nvim_win_get_width(w)
    if math.abs(current_w - target_w) > 1 then needs_resize = true end
    table.insert(targets, {
      win = w,
      from = current_w,
      to = target_w,
    })
  end
  if not has_active then return end
  if not needs_resize then return end

  local step_delay = math.floor(WIN_ANIM_MS / WIN_ANIM_STEPS)
  for step = 1, WIN_ANIM_STEPS do
    vim.defer_fn(function()
      for _, t in ipairs(targets) do
        if vim.api.nvim_win_is_valid(t.win) then
          local eased = -(math.cos(math.pi * (step / WIN_ANIM_STEPS)) - 1) / 2
          vim.api.nvim_win_set_width(t.win, math.floor(t.from + (t.to - t.from) * eased))
        end
      end
    end, step_delay * step)
  end
end

apply_window_layout = function()
  local explorer_fixed = fix_explorer_width()
  local highlight_fixed = fix_explorer_current_file_highlight()
  local normal, min_col = get_normal_wins()

  if #normal == 2 then
    rebalance_two_wins(normal, min_col)
  elseif #normal > 2 then
    win_expand_layout(normal, min_col)
  end

  return explorer_fixed and highlight_fixed
end

vim.api.nvim_create_augroup("win_expand", { clear = true })
vim.api.nvim_create_autocmd("WinEnter", {
  group = "win_expand",
  desc = "Auto-expand focused buffer, keep snacks explorer fixed",
  callback = function()
    if vim.api.nvim_win_get_config(0).relative ~= "" then return end
    if vim.bo.filetype:match("^snacks_") then return end
    apply_window_layout()
  end,
})
vim.api.nvim_create_autocmd("VimResized", {
  group = "win_expand",
  desc = "Reapply explorer and focused window widths after terminal resize",
  callback = function()
    apply_window_layout()
  end,
})
vim.api.nvim_create_autocmd("WinClosed", {
  group = "win_expand",
  desc = "Rebalance remaining splits after a window is closed",
  callback = function()
    vim.schedule(function() apply_window_layout() end)
  end,
})

vim.api.nvim_create_augroup("snacks_explorer_highlight", { clear = true })
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "VimResized" }, {
  group = "snacks_explorer_highlight",
  desc = "Keep explorer current-file highlight color consistent",
  callback = function()
    vim.schedule(function()
      local synced = sync_explorer_to_current_buffer()
      fix_explorer_current_file_highlight()
      if not synced then
        vim.defer_fn(function()
          sync_explorer_to_current_buffer()
          fix_explorer_current_file_highlight()
        end, 300)
      end
    end)
  end,
})

-- Manual equalize: <C-w>=
vim.keymap.set("n", "<C-w>=", function()
  local normal, min_col = get_normal_wins()
  if #normal == 0 then return end
  local equal_w = math.floor((vim.o.columns - min_col - (#normal - 1)) / #normal)
  for _, w in ipairs(normal) do
    vim.api.nvim_win_set_width(w, equal_w)
  end
end, { desc = "Equalize normal windows (keep explorer fixed)" })


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

-- DEBUG: :WinInfo — prints all window info + explorer picker state
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
  local picker = get_explorer_picker()
  if picker then
    local layout = picker.layout
    if layout and layout.root then
      table.insert(lines, string.format("PICKER root.win=%d root_width=%d",
        layout.root.win or -1,
        layout.root.win and vim.api.nvim_win_get_width(layout.root.win) or -1))
    end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, {})
