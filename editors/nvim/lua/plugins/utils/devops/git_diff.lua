---------------------------------------------------------------------------
-- Git diff in a side split.
--
-- The devops diff styling (colored hunks, gutters, file/hunk separators), but
-- shown in a plain, closable vertical split on the right — not the full-screen
-- float the dashboard uses. Your neo-tree and current buffer stay put; open and
-- close it freely while coding.
--
-- Two modes:
--   file  — follows the current buffer: shows that file's diff, and re-targets
--           automatically as you move between files. (default)
--   all   — the whole repo's diff, every changed file at once (]f/[f to jump).
--
-- Live update (file mode): by default the diff reflects the *unsaved* buffer as
-- you type — it diffs the live buffer against the git index/HEAD, no save needed.
--
-- Follow scrolling: the split also tracks your cursor — move around the file and
-- the diff scrolls to the matching line (in "all" mode it jumps to the right
-- file too), without stealing focus. `f` toggles it in the split.
--
-- Configure via vim.g.devops.diff = { live = true|false, debounce = <ms>,
-- follow = true|false }.
--
-- Base defaults to the working-tree diff (`git diff` / index); <Tab> toggles to
-- "all uncommitted vs HEAD" (`git diff HEAD`).
--
--   :DevOpsDiff      toggle the follow-current-file split   (keys.diff,     <leader>dv)
--   :DevOpsDiffAll   toggle the all-changes split           (keys.diff_all, <leader>dV)
--
-- In the split:  <Tab> base · a file/all · ]f [f file · f follow · T theme · R refresh · q close
---------------------------------------------------------------------------

local M = {}

local diff_viewer = require("plugins.utils.devops.ui.diff_viewer")
local render = require("plugins.utils.devops.ui.render")
local config = require("plugins.utils.devops.config")

local augroup = vim.api.nvim_create_augroup("DevOpsGitDiff", { clear = true })

local state = {
  win = nil,             -- the diff split window
  buf = nil,             -- the diff scratch buffer
  src_win = nil,         -- window to return focus to on close
  file = nil,            -- absolute path of the file in focus (nil = none)
  dir = nil,             -- directory to run git in
  base = "working",      -- "working" (git diff / index) | "HEAD" (git diff HEAD)
  mode = "file",         -- "file" (follows buffer) | "all" (whole repo)
  text = "",             -- last diff output (for width re-renders)
  file_positions = {},   -- line of each file header, for ]f/[f
  seq = 0,               -- render sequence, to drop stale async results
  follow = true,         -- scroll the split to the cursor's line (f toggles)
  follow_index = {},     -- [diff path] = sorted { src = file line, buf = diff line }
  follow_line = nil,     -- last diff line we scrolled to, to skip redundant work
}

local function diff_cfg() return config.options.diff or {} end

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- Count editor windows still showing a real, on-disk file — excludes the diff
-- split itself, neo-tree, terminals, and empty [No Name] buffers. When this hits
-- zero the diff must not linger (it would keep Neovim alive on its own).
local function content_windows_left()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= state.win then
      local b = vim.api.nvim_win_get_buf(w)
      if vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then
        n = n + 1
      end
    end
  end
  return n
end

local function close()
  pcall(vim.api.nvim_clear_autocmds, { group = augroup })
  local win = state.win
  state.win = nil -- guard the WinClosed handler against re-entry
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  if state.src_win and vim.api.nvim_win_is_valid(state.src_win) then
    pcall(vim.api.nvim_set_current_win, state.src_win)
  end
  state.buf, state.file, state.dir, state.src_win = nil, nil, nil, nil
end

-- Winbar: mode/filename + current base + key hints, using devops highlight groups.
local function set_winbar(win)
  local head
  if state.mode == "all" then
    head = "%#DevOpsTitle# all changes "
  else
    local name = state.file and vim.fn.fnamemodify(state.file, ":."):gsub("%%", "%%%%") or "no file"
    head = "%#DevOpsTitle# " .. name .. " "
  end
  local base_label = state.base == "HEAD" and "vs HEAD" or "unstaged"
  if state.mode == "file" and diff_cfg().live then base_label = base_label .. " · live" end
  if state.follow then base_label = base_label .. " · follow" end
  local mode_hint = state.mode == "all" and "a %#DevOpsAction#file  " or "a %#DevOpsAction#all  "
  vim.wo[win].winbar = table.concat({
    head,
    "%#DevOpsDim#· ", base_label, "  ",
    "%#DevOpsKey#<Tab> %#DevOpsAction#base  ",
    "%#DevOpsKey#", mode_hint,
    "%#DevOpsKey#]f %#DevOpsAction#file  ",
    "%#DevOpsKey#f %#DevOpsAction#follow  ",
    "%#DevOpsKey#T %#DevOpsAction#theme  ",
    "%#DevOpsKey#q %#DevOpsAction#close",
  })
end

---------------------------------------------------------------------------
-- Diff producers (each calls cb(diff_text) on the main loop)
---------------------------------------------------------------------------

-- On-disk diff via plain git (used for "all" mode, and file mode when live off).
local function disk_diff(cb)
  local dir = state.dir or vim.fn.getcwd()
  local args = { "git", "-C", dir, "diff" }
  if state.base == "HEAD" then args[#args + 1] = "HEAD" end
  if state.mode == "file" and state.file then
    vim.list_extend(args, { "--", state.file }) -- "all" mode: no pathspec = whole repo
  end
  vim.system(args, { text = true }, function(res)
    vim.schedule(function() cb((res.code == 0 and res.stdout) or "") end)
  end)
end

-- Rewrite the `git diff --no-index` temp-file paths back to the real file, so
-- the viewer shows the right name and our parser reads correct titles.
local function rewrite_headers(raw, rel, base_empty)
  if raw == "" then return "" end
  local lines = vim.split(raw, "\n", { plain = true })
  for i, l in ipairs(lines) do
    if l:match("^diff %-%-git ") then
      lines[i] = "diff --git a/" .. rel .. " b/" .. rel
    elseif l:match("^%-%-%- ") then
      lines[i] = base_empty and "--- /dev/null" or ("--- a/" .. rel)
    elseif l:match("^%+%+%+ ") then
      lines[i] = "+++ b/" .. rel
      break -- headers done; the rest are hunks
    end
  end
  return table.concat(lines, "\n")
end

-- Live diff of the *unsaved* buffer for state.file against the git base
-- (index for "working", HEAD for "HEAD"). Falls back to disk_diff when the
-- file has no loaded buffer.
local function live_diff(cb, fallback)
  local file = state.file
  local bufnr = file and vim.fn.bufnr(file) or -1
  if not file or bufnr < 0 or not vim.api.nvim_buf_is_loaded(bufnr) then
    return fallback()
  end
  local dir = state.dir or vim.fn.getcwd()
  local rel = vim.fn.fnamemodify(file, ":.")
  local obj = (state.base == "HEAD" and "HEAD:./" or ":./") .. vim.fn.fnamemodify(file, ":t")
  -- Base blob content (empty + base_empty when the file isn't tracked at this base).
  vim.system({ "git", "-C", dir, "show", obj }, { text = true }, function(res)
    local base_content = (res.code == 0) and (res.stdout or "") or ""
    local base_empty = (res.code ~= 0)
    vim.schedule(function()
      if not is_open() then return end
      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      if vim.bo[bufnr].eol ~= false then buf_lines[#buf_lines + 1] = "" end -- trailing newline
      local base_tmp, buf_tmp = vim.fn.tempname(), vim.fn.tempname()
      local function cleanup()
        os.remove(base_tmp)
        os.remove(buf_tmp)
      end
      -- A failed write would leave git diffing an empty/missing file and quietly
      -- render a bogus diff, so fall back to the on-disk diff instead.
      local wrote = pcall(function()
        assert(vim.fn.writefile(vim.split(base_content, "\n", { plain = true }), base_tmp, "b") == 0)
        assert(vim.fn.writefile(buf_lines, buf_tmp, "b") == 0)
      end)
      if not wrote then
        cleanup()
        return fallback()
      end
      vim.system(
        { "git", "-C", dir, "--no-pager", "diff", "--no-index", "--unified=3", "--", base_tmp, buf_tmp },
        { text = true },
        function(res2)
          vim.schedule(function()
            cleanup()
            cb(rewrite_headers(res2.stdout or "", rel, base_empty))
          end)
        end)
    end)
  end)
end

---------------------------------------------------------------------------
-- Follow the cursor
--
-- The renderer hands back a line_map (diff line -> source file + line). We
-- invert it into per-file arrays sorted by source line, so a cursor move is a
-- binary search plus, at most, one winrestview.
---------------------------------------------------------------------------

-- Deleted lines are numbered against the *old* file, so they'd point somewhere
-- else in the buffer you're editing — index additions and context only.
local function build_follow_index(line_map)
  local idx = {}
  for buf_line, e in pairs(line_map or {}) do
    if e.kind ~= "del" and e.path and e.path ~= "" and e.line then
      local entries = idx[e.path]
      if not entries then
        entries = {}
        idx[e.path] = entries
      end
      entries[#entries + 1] = { src = e.line, buf = buf_line }
    end
  end
  for _, entries in pairs(idx) do
    table.sort(entries, function(a, b) return a.src < b.src end)
  end
  return idx
end

-- Diff paths are repo-relative, the buffer's is absolute: match on the longest
-- path that the absolute name ends with, so a/b/x.lua doesn't win over b/x.lua.
local function entries_for(abs)
  local best, best_len
  for path, entries in pairs(state.follow_index) do
    if abs == path or abs:sub(-(#path + 1)) == "/" .. path then
      if not best_len or #path > best_len then best, best_len = entries, #path end
    end
  end
  return best
end

-- Entry whose source line is closest to `src` (entries are sorted by src).
local function nearest_entry(entries, src)
  local lo, hi, at = 1, #entries, nil
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if entries[mid].src <= src then
      at = mid
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  if not at then return entries[1] end
  local before, after = entries[at], entries[at + 1]
  if after and (after.src - src) < (src - before.src) then return after end
  return before
end

-- Put the diff's cursor on `line`, scrolling only when it nears an edge — a
-- recenter on every keystroke would make the split jitter as you move.
local function scroll_to(line)
  line = math.max(1, math.min(line, vim.api.nvim_buf_line_count(state.buf)))
  if state.follow_line == line then return end
  state.follow_line = line
  vim.api.nvim_win_call(state.win, function()
    local view = vim.fn.winsaveview()
    local height = vim.api.nvim_win_get_height(state.win)
    local margin = math.min(4, math.floor(height / 5))
    if line < view.topline + margin or line > view.topline + height - 1 - margin then
      view.topline = math.max(1, line - math.floor(height / 2))
    end
    view.lnum, view.col, view.curswant, view.coladd = line, 0, 0, 0
    vim.fn.winrestview(view)
  end)
end

-- Scroll the split to whatever line `win` (a normal file window) sits on.
local function follow_cursor(win)
  if not state.follow or not is_open() then return end
  win = win or vim.api.nvim_get_current_win()
  if win == state.win or not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return end
  local entries = entries_for(vim.fn.fnamemodify(name, ":p"))
  if not entries or #entries == 0 then return end -- file has no changes in view
  local target = nearest_entry(entries, vim.api.nvim_win_get_cursor(win)[1])
  if target then scroll_to(target.buf) end
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

local function refresh()
  if not is_open() then return end
  state.seq = state.seq + 1
  local seq = state.seq
  local function paint(text)
    if not is_open() or seq ~= state.seq then return end -- a newer refresh superseded us
    state.text = text or ""
    local info = diff_viewer.render_unified_into(
      state.buf, vim.api.nvim_win_get_width(state.win), state.text)
    state.file_positions = info.file_positions or {}
    state.follow_index = build_follow_index(info.line_map)
    state.follow_line = nil -- the lines moved; re-follow even if the number matches
    set_winbar(state.win)
    follow_cursor()
  end
  if diff_cfg().live and state.mode == "file" and state.file then
    live_diff(paint, function() disk_diff(paint) end)
  else
    disk_diff(paint)
  end
end

-- Debounced live refresh, so typing doesn't spawn a git process per keystroke.
local live_token = 0
local function schedule_live()
  live_token = live_token + 1
  local my = live_token
  vim.defer_fn(function()
    if my == live_token and is_open() then refresh() end
  end, diff_cfg().debounce or 150)
end

-- Move the cursor to the next/previous file header (useful in "all" mode).
local function jump_file(delta)
  local pos = state.file_positions
  if not pos or #pos == 0 or not is_open() then return end
  local cur = vim.api.nvim_win_get_cursor(state.win)[1] - 1
  local target
  if delta > 0 then
    for _, p in ipairs(pos) do if p > cur then target = p break end end
    target = target or pos[1]
  else
    for i = #pos, 1, -1 do if pos[i] < cur then target = pos[i] break end end
    target = target or pos[#pos]
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { target + 1, 0 })
end

local function keymaps(buf)
  local function m(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  m("q", close, "Close git diff")
  m("<Tab>", function()
    state.base = state.base == "HEAD" and "working" or "HEAD"
    refresh()
  end, "Toggle diff base (unstaged / vs HEAD)")
  m("a", function()
    state.mode = state.mode == "all" and "file" or "all"
    refresh()
  end, "Toggle mode (this file / all changes)")
  m("]f", function() jump_file(1) end, "Next file")
  m("[f", function() jump_file(-1) end, "Prev file")
  m("f", function()
    state.follow = not state.follow
    set_winbar(state.win)
    follow_cursor(state.src_win)
    vim.notify("Diff follow: " .. (state.follow and "on" or "off"),
      vim.log.levels.INFO, { title = "DevOps" })
  end, "Toggle follow scrolling")
  m("T", function()
    -- Extmarks reference the hl groups by name, so recoloring updates live.
    local name = render.cycle_diff_theme(1)
    set_winbar(state.win)
    vim.notify("Diff theme: " .. name, vim.log.levels.INFO, { title = "DevOps" })
  end, "Cycle diff theme")
  m("R", refresh, "Refresh diff")
end

-- Build the split + buffer, wire keymaps/autocmds, then paint the first diff.
local function open_split(mode, file, dir, src_win)
  state.mode = mode
  state.file = file
  state.dir = dir
  state.src_win = src_win
  state.follow = diff_cfg().follow ~= false
  state.follow_index, state.follow_line = {}, nil

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "DevOpsGitDiff" -- unknown ft → no LSP/treesitter, just our colors
  vim.bo[buf].modifiable = false
  state.buf = buf

  -- Full-height vertical split on the far right; leaves neo-tree + the buffer alone.
  vim.cmd("botright vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  state.win = win
  pcall(vim.cmd, "vertical resize " .. math.max(60, math.floor(vim.o.columns * 0.45)))

  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].winfixwidth = true
  vim.wo[win].winhighlight = "CursorLine:Visual"

  keymaps(buf)
  set_winbar(win)

  -- Re-render on save; live-update as you type; on resize (separators track
  -- width); follow the buffer in "file" mode; clean up on external close (:q…).
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup, pattern = "*",
    callback = function() refresh() end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup,
    callback = function(ev)
      if not diff_cfg().live or not is_open() or state.mode ~= "file" then return end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name == "" or vim.fn.fnamemodify(name, ":p") ~= state.file then return end
      schedule_live()
    end,
  })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = augroup,
    callback = function()
      if is_open() and state.text ~= "" then
        local info = diff_viewer.render_unified_into(
          state.buf, vim.api.nvim_win_get_width(state.win), state.text)
        state.follow_index = build_follow_index(info.line_map)
        state.follow_line = nil
        follow_cursor()
      end
    end,
  })
  -- Follow scrolling: track the cursor of whatever file window you're in.
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function(ev)
      if not is_open() or ev.buf == state.buf then return end
      follow_cursor()
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(ev)
      if state.mode ~= "file" or not is_open() then return end
      if ev.buf == state.buf then return end          -- entering the diff itself
      if vim.bo[ev.buf].buftype ~= "" then return end -- neo-tree, terminals, prompts…
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name == "" then return end
      name = vim.fn.fnamemodify(name, ":p")
      if name == state.file then return end           -- already showing this file
      state.file = name
      state.dir = vim.fn.fnamemodify(name, ":h")
      local w = vim.api.nvim_get_current_win()
      if w ~= state.win then state.src_win = w end     -- return here on close
      refresh()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup, pattern = tostring(win),
    callback = function() close() end,
  })
  -- When the buffer/window it follows goes away and no file window is left, close
  -- the diff too — so closing your last file still collapses neo-tree and exits.
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "WinClosed" }, {
    group = augroup,
    callback = function(ev)
      if not is_open() then return end
      if ev.event == "WinClosed" and tonumber(ev.match) == state.win then return end -- our own
      if ev.buf == state.buf then return end
      vim.schedule(function() -- let the window/buffer teardown settle first
        if is_open() and content_windows_left() == 0 then close() end
      end)
    end,
  })

  -- In "file" mode keep coding — hand focus back so the diff can follow you.
  -- In "all" mode stay in the split to review.
  if mode == "file" and src_win and vim.api.nvim_win_is_valid(src_win) then
    vim.api.nvim_set_current_win(src_win)
  end

  refresh()
end

-- Current file (nil if the buffer isn't a real file), a dir to run git in, and
-- the window to return focus to.
local function context()
  local src_buf = vim.api.nvim_get_current_buf()
  local src_win = vim.api.nvim_get_current_win()
  local name = vim.api.nvim_buf_get_name(src_buf)
  local file
  if name ~= "" and vim.bo[src_buf].buftype == "" then
    file = vim.fn.fnamemodify(name, ":p")
  end
  local dir = file and vim.fn.fnamemodify(file, ":h") or vim.fn.getcwd()
  return file, dir, src_win
end

-- Open the split fresh in `mode`, after confirming we're in a git work tree.
local function open(mode)
  local file, dir, src_win = context()
  if mode == "file" and not file then
    vim.notify("DevOps diff: current buffer is not a file on disk", vim.log.levels.WARN)
    return
  end
  vim.system({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" }, { text = true },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 or not (res.stdout or ""):match("true") then
          vim.notify("DevOps diff: not inside a git repository", vim.log.levels.WARN)
          return
        end
        if is_open() then close() end
        open_split(mode, file, dir, src_win)
      end)
    end)
end

-- Toggle the split for `mode`: close if already in that mode, switch if open in
-- the other mode, else open fresh.
local function toggle(mode)
  if is_open() then
    if state.mode == mode then
      close()
    else
      state.mode = mode
      if mode == "file" and state.file then
        state.dir = vim.fn.fnamemodify(state.file, ":h")
      end
      refresh()
    end
  else
    open(mode)
  end
end

--- Toggle the follow-current-file diff split.
function M.toggle() toggle("file") end

--- Toggle the all-changes (whole repo) diff split.
function M.toggle_all() toggle("all") end

return M
