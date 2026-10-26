-- Diff viewer with unified and split view toggle.
--
-- Unified: parsed diff with colored backgrounds, file/hunk headers, sign indicators.
-- Split:   side-by-side with scrollbind, colored backgrounds, empty padding markers.
local M = {}

local ns = vim.api.nvim_create_namespace("DevOpsDiffViewer")
local ns_comments = vim.api.nvim_create_namespace("DevOpsDiffComments")
local ns_blame = vim.api.nvim_create_namespace("DevOpsDiffBlame")
local augroup = vim.api.nvim_create_augroup("DevOpsDiffViewer", { clear = true })
local state = {
  mode = "split",
  title = "",
  diff_text = "",
  parsed = nil,
  wins = {},
  bufs = {},
  prev_win = nil,
  file_positions = {},
  -- PR review context (nil when viewing non-PR diffs)
  pr = nil,       -- { repo = "owner/repo", number = 123 }
  viewed = {},    -- [path] = true for files marked "Viewed" on the PR
  pr_node_id = nil,
  line_map = {},   -- [buf_line_1indexed] = { path = "...", line = N, kind = "add"|"del"|"ctx" }
  pending_comments = {}, -- { { path, line, body }, ... }
  blame_visible = false,
  blame_data = {}, -- [filepath] = { [line_num] = "author date" }
  tree_visible = true, -- left file-tree pane (shown by default; 'f' toggles)
  tree_collapsed = {}, -- [dir_path] = true when collapsed in the tree
}

local render = require("plugins.utils.devops.ui.render")
local errors = require("plugins.utils.devops.ui.errors")
local TREE_W = 38 -- file-tree pane content width
local render_tree_pane, toggle_tree -- forward declarations (defined below)
-- Horizontal space the tree reserves on the left (pane width + its border).
local function tree_off() return state.tree_visible and (TREE_W + 2) or 0 end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function close_windows()
  for _, win in pairs(state.wins) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in pairs(state.bufs) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  state.wins, state.bufs, state.file_positions, state.line_map = {}, {}, {}, {}
  state.page_first, state.page_last, state.on_page, state.tree_goto = nil, nil, nil, nil
  state.tree_refresh = nil
  pcall(vim.api.nvim_clear_autocmds, { group = augroup })
end

-- Separate group: close_windows() clears `augroup` on every re-render, but the
-- resize handler must survive those.
local resize_group = vim.api.nvim_create_augroup("DevOpsDiffViewerResize", { clear = true })
local resize_timer

local function close()
  pcall(vim.api.nvim_clear_autocmds, { group = resize_group })
  if resize_timer then resize_timer:stop() end
  close_windows()
  state.mode = "split"
  state.pr = nil
  state.viewed, state.pr_node_id, state.pr_author = {}, nil, nil
  state.pending_comments = {}
  state.threads, state.thread_at, state.thread_rows = nil, nil, nil
  state.blame_visible = false
  state.blame_data = {}
  state.page, state.page_diff = nil, nil
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    vim.api.nvim_set_current_win(state.prev_win)
  end
  state.prev_win = nil
end

-- Plugins that scroll past the end of the buffer (scrollEOF.nvim pads with the
-- global 'scrolloff') fight the paged view's clamp, so opt these buffers out.
local FT = "devops_diff"
local function exempt_scroll_plugins()
  local ok, se = pcall(require, "scrollEOF")
  if ok and type(se.opts) == "table" and type(se.opts.disabled_filetypes) == "table" then
    se.opts.disabled_filetypes[FT] = true
  end
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = FT
  exempt_scroll_plugins()
  return buf
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function set_win_opts(win)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].scrolloff = 0
  pcall(function() vim.wo[win].scrolloffpad = 0 end) -- nvim 0.13+: no padding past EOF
  vim.wo[win].winhighlight = "FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle,CursorLine:Visual,Folded:NormalFloat"
end

local function file_separator(title, width)
  local dash = "─"
  local label = " " .. title .. " "
  local label_bytes = #label
  -- each ─ is 3 bytes; compute how many dashes fill the remaining width
  local prefix_dashes = 2
  local remaining = math.max(0, (width - label_bytes) / 3 - prefix_dashes)
  local suffix_dashes = math.floor(remaining)
  return string.rep(dash, prefix_dashes) .. label .. string.rep(dash, suffix_dashes)
end

local function sep_rule(width)
  -- "─ ─ ─ ─ …" pattern filling the width (each "─ " is 4 bytes, 2 display chars)
  local pair = "─ "
  local count = math.floor(width / 2)
  return string.rep(pair, count)
end

local function map_buf(buf, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
end

-- Shift+Arrow: tree · left/unified · right, then the adjacent WezTerm pane.
local function pane_order()
  local order = {}
  for _, key in ipairs({ "tree", "unified", "left", "right" }) do
    order[#order + 1] = state.wins[key]
  end
  return order
end

local function map_pane_nav(buf)
  require("plugins.utils.devops.ui.pane_nav").map(buf, { h = pane_order })
end

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

-- Paged view: only the current file is visible. Everything before/after it sits
-- in two closed folds drawn as delimiter bars, and moving (or scrolling) past
-- either edge flips to the adjacent file, so files never bleed into each other.
-- The buffer itself stays whole, so line_map / threads / blame are unaffected.
local PAGE_GAP = 3 -- blank "filegap" lines before each file's rules (never shown)
local paging = false

local function diff_wins()
  local out = {}
  for _, key in ipairs({ "unified", "left", "right" }) do
    local w = state.wins[key]
    if w and vim.api.nvim_win_is_valid(w) then out[#out + 1] = w end
  end
  return out
end

-- 1-based inclusive line range of file `i`'s page: its 2 rules, header, 2 rules, hunks.
local function page_range(i, total)
  local pos = state.file_positions
  local first = pos[i] - 1
  local last = pos[i + 1] and (pos[i + 1] - 2 - PAGE_GAP) or total
  return first, math.max(first, last)
end

-- File index owning buffer line `line` (1-based).
local function page_of(line)
  local pos = state.file_positions
  for i = #pos, 1, -1 do
    if line >= pos[i] - 1 - PAGE_GAP then return i end
  end
  return 1
end

-- Overscroll needed at a page edge before flipping (config ui.diff_overscroll).
local function overscroll_needed()
  local ok, cfg = pcall(require, "plugins.utils.devops.config")
  local n = ok and cfg.options and cfg.options.ui and cfg.options.ui.diff_overscroll
  return math.max(1, tonumber(n) or 2)
end

function M._foldtext()
  return ""
end

-- End/top banners (virtual lines, so the buffer and line_map are untouched): a
-- full-width bar under the page's last line ("END a.lua 1/3 … next ▸ b.lua ]f")
-- and one above its first line, revealed with topfill when scrolling up.
local ns_page = vim.api.nvim_create_namespace("DevOpsDiffPage")
local EDGE_H = 2 -- blank spacer + banner

local function file_name(i)
  local f = state.parsed and state.parsed[i]
  return f and (f.new_path or f.old_path) or ""
end

local dw = vim.fn.strdisplaywidth
local function chunks_w(cs)
  local n = 0
  for _, c in ipairs(cs) do n = n + dw(c[1]) end
  return n
end
-- First layout of `layouts` (widest → most compact) that fits in `width`.
local function fit(layouts, width)
  for _, l in ipairs(layouts) do
    if chunks_w(l) <= width then return l end
  end
  return layouts[#layouts]
end
local function meter(dir)
  local need = overscroll_needed()
  local at = state.over and state.over.dir == dir
  local n = at and state.over.n or 0
  return string.rep("▰", n) .. string.rep("▱", need - n), at and true or false
end

-- Context for the marker at edge `dir` ("down" = end of file, "up" = top).
local function edge_ctx(dir)
  local i, n = state.page, #state.file_positions
  local other = dir == "down" and i + 1 or i - 1
  local bar, hot = meter(dir)
  return {
    i = i, n = n, name = file_name(i), bar = bar, hot = hot,
    has_other = other >= 1 and other <= n,
    other = file_name(other),
    key = dir == "down" and "]f" or "[f",
  }
end

-- banner -----------------------------------------------------------------
local function banner_rows(dir, width)
  local c = edge_ctx(dir)
  local bg = c.hot and "DevOpsDiffBannerHot" or "DevOpsDiffBanner"
  local function h(g) return g and { bg, g } or bg end
  local tag = dir == "down" and (c.has_other and " END " or " END OF DIFF ") or " TOP "
  local left = { { " " .. tag, h("DevOpsDiffBannerTag") }, { "  ", h() },
    { c.name, h("DevOpsId") }, { ("  %d/%d"):format(c.i, c.n), h() } }
  local right
  if c.has_other then
    local arrow = dir == "down" and "next ▸ " or "◂ prev "
    right = fit({
      { { arrow, h() }, { c.other, h("DevOpsId") }, { "   " .. c.bar .. "  ", h() }, { c.key, h("DevOpsKey") }, { " ", h() } },
      { { arrow, h() }, { vim.fs.basename(c.other), h("DevOpsId") }, { "  " .. c.bar .. " ", h() }, { c.key, h("DevOpsKey") }, { " ", h() } },
      { { c.bar .. " ", h() }, { c.key, h("DevOpsKey") }, { " ", h() } },
    }, math.max(10, width - chunks_w(left) - 2))
  else
    right = fit({
      { { "✓ last file   ", h("DevOpsOk") }, { "[f", h("DevOpsKey") }, { " prev  ", h() }, { "q", h("DevOpsKey") }, { " close ", h() } },
      { { "✓ ", h("DevOpsOk") } },
    }, math.max(4, width - chunks_w(left) - 2))
  end
  local over = chunks_w(left) + chunks_w(right) - width
  if over > 0 then left[3][1] = render.truncate(c.name, math.max(3, dw(c.name) - over)) end
  local row = vim.list_extend(left, { { string.rep(" ", math.max(1, width - chunks_w(left) - chunks_w(right))), h() } })
  vim.list_extend(row, right)
  if dir == "down" then return { { { "", "Normal" } }, row } end
  return { row, { { "", "Normal" } } }
end

-- Virtual lines drawn under buffer row `row` (1-based), from any namespace
-- (end banner, review threads). nvim_win_text_height leaves these out when
-- `row` ends the measured range.
local function rows_below(buf, row)
  local n = 0
  local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, -1, { row - 1, 0 }, { row - 1, -1 }, { details = true })
  for _, m in ipairs(ok and marks or {}) do
    if m[4].virt_lines and not m[4].virt_lines_above then n = n + #m[4].virt_lines end
  end
  return n
end

local function paint_cards()
  if not state.page or not state.page_first then return end
  for _, w in ipairs(diff_wins()) do
    local buf = vim.api.nvim_win_get_buf(w)
    local width = vim.api.nvim_win_get_width(w)
    vim.api.nvim_buf_clear_namespace(buf, ns_page, 0, -1)
    local down = banner_rows("down", width)
    -- Short page: pad so the end marker sits on the window's last row instead
    -- of floating mid-screen above empty space.
    local ok_h, th = pcall(vim.api.nvim_win_text_height, w,
      { start_row = state.page_first - 1, end_row = state.page_last - 1 })
    local fill = vim.api.nvim_win_call(w, function() return vim.fn.winsaveview().topfill or 0 end)
    local pad = ok_h and (vim.api.nvim_win_get_height(w) - th.all - rows_below(buf, state.page_last) - #down - fill) or 0
    for _ = 1, pad do table.insert(down, 1, { { "", "Normal" } }) end
    state.painted_fill = fill
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_page, state.page_last - 1, 0, { virt_lines = down })
    if state.page > 1 then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_page, state.page_first - 1, 0,
        { virt_lines = banner_rows("up", width), virt_lines_above = true })
    end
  end
end

-- Highest topline of window `w` that still fills it with the page, so the end
-- marker (+ the fold line under it) are the last rows. Counted in screen rows,
-- so review threads / padding (virtual lines) are accounted for.
local function max_top(w)
  local buf = vim.api.nvim_win_get_buf(w)
  local h = vim.api.nvim_win_get_height(w)
  local base = rows_below(buf, state.page_last) + (state.page_last < vim.api.nvim_buf_line_count(buf) and 1 or 0)
  for t = state.page_last, state.page_first + 1, -1 do
    local ok, th = pcall(vim.api.nvim_win_text_height, w, { start_row = t - 1, end_row = state.page_last - 1 })
    if (ok and th.all or (state.page_last - t + 1)) + base >= h then return t end
  end
  return state.page_first
end

--- Show file `i` as the page. `where`: "top" (header at the top), "bottom"
--- (cursor on the last line) or a buffer line to put the cursor on.
local function show_page(i, where)
  local pos = state.file_positions
  local wins = diff_wins()
  if #pos == 0 or #wins == 0 then return end
  i = math.max(1, math.min(i, #pos))
  state.page, state.over = i, nil
  paging = true
  -- Unbind while positioning: scrollbind would shift the other pane by the
  -- (fold-dependent) scroll delta and leak the neighbouring file's bar in.
  local bound = {}
  for _, w in ipairs(wins) do
    bound[w] = vim.wo[w].scrollbind
    vim.wo[w].scrollbind, vim.wo[w].cursorbind = false, false
  end
  for _, w in ipairs(wins) do
    local total = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(w))
    local first, last = page_range(i, total)
    state.page_first, state.page_last = first, last
    vim.api.nvim_win_call(w, function()
      vim.wo.foldmethod = "manual"
      vim.wo.foldenable = true
      vim.wo.foldlevel = 0
      vim.wo.foldminlines = 0
      vim.wo.foldcolumn = "0"
      vim.wo.fillchars = "fold: ,eob: "
      vim.wo.foldtext = "v:lua.require'plugins.utils.devops.ui.diff_viewer'._foldtext()"
      vim.cmd("silent! normal! zE")
      if first > 1 then vim.cmd(("silent! 1,%dfold"):format(first - 1)) end
      if last < total then vim.cmd(("silent! %d,%dfold"):format(last + 1, total)) end
      vim.fn.winrestview({ topfill = 0 })
    end)
  end
  paint_cards()
  for _, w in ipairs(wins) do
    local first, last = state.page_first, state.page_last
    local h = vim.api.nvim_win_get_height(w)
    local lnum, top
    if where == "bottom" then
      lnum, top = last, max_top(w)
    elseif type(where) == "number" then
      lnum = math.max(first, math.min(where, last))
      top = math.max(first, math.min(lnum - math.floor(h / 2), max_top(w)))
    else
      lnum, top = math.min(pos[i] + 1, last), first
    end
    vim.api.nvim_win_call(w, function()
      -- `zt` (not winrestview's topline, which gets clamped on a short last
      -- page) so the bar above is scrolled out of view.
      vim.api.nvim_win_set_cursor(0, { top, 0 })
      vim.cmd("normal! zt")
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      vim.fn.winrestview({ topfill = 0 })
    end)
  end
  for _, w in ipairs(wins) do
    if bound[w] then vim.wo[w].scrollbind, vim.wo[w].cursorbind = true, true end
  end
  paging = false
  if state.tree_goto then state.tree_goto(i) end
  if state.on_page then state.on_page() end
end

-- Overscroll: reaching a page edge is a hard stop (the banner lights up, ▱▱).
-- After that, N separate scrolls (ui.diff_overscroll) fill the meter and the
-- Nth flips to the adjacent file. Events within BURST_MS of the last counted
-- one (wheel momentum, a held j) merge into it, idle time resets the stop, and a cooldown
-- after a flip keeps momentum from skipping through several files.
local BURST_MS, RESET_MS, COOLDOWN_MS = 120, 1200, 300
M._now = function() return vim.uv.hrtime() / 1e6 end
local over_timer
local flipped_at = -1e9
local function arm_reset()
  over_timer = over_timer or vim.uv.new_timer()
  over_timer:stop()
  over_timer:start(RESET_MS, 0, vim.schedule_wrap(function()
    state.over = nil
    paint_cards()
  end))
end

local function main_win()
  local w = state.wins.left or state.wins.unified
  return w and vim.api.nvim_win_is_valid(w) and w or nil
end

local function overscroll(dir)
  local now = M._now()
  if now - flipped_at < COOLDOWN_MS then return end
  local can = dir == "down" and state.page < #state.file_positions or dir == "up" and state.page > 1
  if not can then return end
  local over = state.over
  if not (over and over.dir == dir and now - over.at < RESET_MS) then
    state.over = { dir = dir, n = 0, at = now, mark = now } -- the stop
  else
    over.at = now
    -- merge only events right after the last counted one (momentum / key
    -- repeat); a steady wheel still counts one scroll every BURST_MS
    if now - over.mark < BURST_MS then return end
    over.mark = now
    over.n = over.n + 1
    if over.n >= overscroll_needed() then
      state.over, flipped_at = nil, now
      show_page(state.page + (dir == "down" and 1 or -1), dir == "down" and "top" or "bottom")
      -- Landed on a page that already fits the window: you're at its edge, so
      -- that counts as the stop (no scrolling through empty space first).
      local w = main_win()
      if w and max_top(w) == state.page_first then
        state.over = { dir = dir, n = 0, at = now, mark = now }
        paint_cards()
        arm_reset()
      end
      return
    end
  end
  paint_cards()
  arm_reset()
end

-- Keep the view on the page: never scrolled past it — at most a bar sits on the
-- first/last row. Returns the direction it had to clamp ("up"/"down") or nil.
local function clamp_view()
  local main = main_win()
  if not main then return end
  local top = vim.api.nvim_win_call(main, function() return vim.fn.line("w0") end)
  local mt = max_top(main)
  local dir, clamp
  if top > mt then dir, clamp = "down", mt
  elseif top < state.page_first then dir, clamp = "up", state.page_first end
  if not dir then return end
  paging = true
  for _, w in ipairs(diff_wins()) do
    vim.api.nvim_win_call(w, function()
      local lnum = math.max(clamp, math.min(vim.fn.line("."), state.page_last))
      local fill = (dir == "up" and state.page > 1) and EDGE_H or 0
      vim.fn.winrestview({ topline = clamp, topfill = fill, lnum = lnum })
    end)
  end
  paging = false
  return dir
end

-- Cursor stepped onto a bar (j/k past the edge): keep it on the page and count.
local function on_diff_cursor()
  if paging or not state.page_first then return end
  local l = vim.api.nvim_win_get_cursor(0)[1]
  local dir
  if l > state.page_last then dir = "down" elseif l < state.page_first then dir = "up" end
  if not dir then return end
  -- A jump into another file (search /?nN, marks, :N) lands past the edge inside
  -- an opened fold (or mid-fold); j/k only reach the closed fold's first line.
  local fc = vim.fn.foldclosed(l)
  local far = (dir == "down" and l > state.page_last + 1) or (dir == "up" and l < state.page_first - 1)
  if far and fc ~= l then
    local target = page_of(l)
    if target ~= state.page then return show_page(target, l) end
  end
  paging = true
  local back = dir == "down" and state.page_last or state.page_first
  for _, w in ipairs(diff_wins()) do pcall(vim.api.nvim_win_set_cursor, w, { back, 0 }) end
  paging = false
  clamp_view()
  overscroll(dir)
end

-- View scrolled (wheel, Ctrl-e/y…) past the page: clamp it and count the attempt.
local function on_diff_scroll()
  if paging or not state.page_first then return end
  local dir = clamp_view()
  if dir then return overscroll(dir) end
  -- the top marker scrolled in/out of view: re-pad the end marker
  local w = main_win()
  local fill = w and vim.api.nvim_win_call(w, function() return vim.fn.winsaveview().topfill or 0 end)
  if fill and fill ~= state.painted_fill then paint_cards() end
end
M._on_scroll = on_diff_scroll

-- Put the cursor on buffer line `line`, switching to its file's page.
local function goto_line(line)
  show_page(page_of(line), line)
end

-- Next/prev file, skipping files marked viewed (unless every other one is).
function M._next_file(cur, delta, n, viewed_at)
  for step = 1, n - 1 do
    local i = (cur - 1 + delta * step) % n + 1
    if not viewed_at(i) then return i end
  end
  return (cur - 1 + delta) % n + 1
end

local function is_viewed(i) return state.viewed[file_name(i)] == true end

local function jump_file(delta)
  local n = #state.file_positions
  if n == 0 then return end
  show_page(M._next_file(state.page or 1, delta, n, is_viewed), "top")
end

-- GitHub's per-file "Viewed" checkbox. Marking the page's file from the diff
-- moves on to the next unviewed file, like the web UI collapsing it.
local function toggle_viewed(idx, advance)
  if not state.pr then
    return vim.notify("DevOps: viewed marks need a PR diff", vim.log.levels.INFO)
  end
  if not state.pr_node_id then
    return vim.notify("DevOps: viewed state still loading…", vim.log.levels.INFO)
  end
  idx = idx or state.page
  local path = file_name(idx)
  if path == "" then return end
  local now = not state.viewed[path]
  state.viewed[path] = now or nil
  if state.tree_refresh then state.tree_refresh() end
  if state.on_page then state.on_page() end
  require("plugins.utils.devops.github.api").set_file_viewed(state.pr_node_id, path, now, function(ok, _, err)
    if ok then return end
    state.viewed[path] = (not now) or nil
    if state.tree_refresh then state.tree_refresh() end
    if state.on_page then state.on_page() end
    vim.notify("DevOps: couldn't update viewed — " .. (err or "?"), vim.log.levels.WARN)
  end)
  if now and advance and idx == state.page then
    local n = #state.file_positions
    local nxt = M._next_file(idx, 1, n, is_viewed)
    if not is_viewed(nxt) then show_page(nxt, "top") end
  end
end
M._toggle_viewed = toggle_viewed

---------------------------------------------------------------------------
-- Inline comments & review submission
---------------------------------------------------------------------------

local input = require("plugins.utils.devops.ui.input")
local gh = require("plugins.utils.devops.github.api")
local store = require("plugins.utils.devops.store")

-- Persisted draft review comments, keyed "repo#number", so an in-progress review
-- survives closing/reopening the diff and Neovim restarts.
local pending_by_pr -- lazy-loaded map

local function pending_key()
  return state.pr and (state.pr.repo .. "#" .. tostring(state.pr.number)) or nil
end
local function load_pending_store()
  if not pending_by_pr then pending_by_pr = store.load_pending() or {} end
  return pending_by_pr
end
local function save_pending_store()
  if not pending_by_pr then return end
  for k, v in pairs(pending_by_pr) do
    if type(v) ~= "table" or #v == 0 then pending_by_pr[k] = nil end
  end
  pcall(store.save_pending, pending_by_pr)
end
-- Bind state.pending_comments to this PR's persisted draft list (same table).
local function bind_pending()
  local key = pending_key()
  if not key then return end
  load_pending_store()
  pending_by_pr[key] = pending_by_pr[key] or {}
  state.pending_comments = pending_by_pr[key]
end

local function get_line_info()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_map[line]
end

-- Diff lines around `row` (1-based, current window) for the comment preview,
-- staying within the same file and keeping the diff highlights.
local CONTEXT = 6
local function comment_preview(row, path, title)
  local buf = vim.api.nvim_get_current_buf()
  local total = vim.api.nvim_buf_line_count(buf)
  local function same_file(r)
    local m = state.line_map[r]
    return not m or m.path == path
  end
  local first, last = row, row
  while first > 1 and row - first < CONTEXT and same_file(first - 1) do first = first - 1 end
  while last < total and last - row < CONTEXT and same_file(last + 1) do last = last + 1 end
  return {
    title = title,
    lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false),
    extmarks = input.extmarks_from(buf, ns, first - 1, last - 1),
    focus = row - first + 1,
    wrap = false,
  }
end

-- Preview for an existing pending comment: find its row in the open diff.
local function pending_preview(c)
  for _, key in ipairs({ "unified", "right" }) do
    local w = state.wins[key]
    if w and vim.api.nvim_win_is_valid(w) then
      for r, m in pairs(state.line_map) do
        if m.path == c.path and m.line == c.line then
          return vim.api.nvim_win_call(w, function()
            return comment_preview(r, c.path, c.path .. ":" .. c.line)
          end)
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Existing review threads, shown as virtual lines under the line they're on
-- (split: on the commented side, padded on the other so scrollbind stays aligned).
---------------------------------------------------------------------------
local ns_threads = vim.api.nvim_create_namespace("DevOpsDiffThreads")
local MAX_BODY = 8

local function wrap_text(text, width)
  local out = {}
  for _, para in ipairs(vim.split(text or "", "\n", { plain = true })) do
    para = para:gsub("\r", "")
    if not para:match("%S") then
      if #out > 0 and out[#out] ~= "" then out[#out + 1] = "" end
    else
      local indent = para:match("^%s*")
      local line = ""
      for word in para:gmatch("%S+") do
        if line == "" then
          line = indent .. word
        elseif vim.fn.strdisplaywidth(line) + 1 + vim.fn.strdisplaywidth(word) > width then
          out[#out + 1] = line
          line = indent .. word
        else
          line = line .. " " .. word
        end
      end
      out[#out + 1] = line
    end
  end
  while #out > 0 and out[#out] == "" do table.remove(out) end
  return out
end

-- Plain-text lines (with highlight) for one thread.
local function thread_lines(t, width)
  local me = gh.current_user_login()
  local clean = require("plugins.utils.devops.ui.markdown").clean
  local w = math.max(30, math.min(width - 8, 110))
  local out = {}
  local all = { t.root }
  vim.list_extend(all, t.replies)
  for i, c in ipairs(all) do
    local who = c.user and c.user.login or "?"
    out[#out + 1] = { (i == 1 and "┌ 💬 @" or "├ ↳ @") .. who .. "  " .. (c.created_at or ""):sub(1, 10),
      who == me and "DevOpsOk" or "DevOpsKey" }
    local ok, cleaned = pcall(clean, c.body or "")
    for j, l in ipairs(wrap_text(ok and cleaned or (c.body or ""), w)) do
      if j > MAX_BODY then out[#out + 1] = { "│   …", "DevOpsDim" } break end
      out[#out + 1] = { "│   " .. l, "DevOpsThreadText" }
    end
  end
  out[#out + 1] = { ("└ r reply · ]c/[c threads · %d comment%s"):format(#all, #all == 1 and "" or "s"), "DevOpsDim" }
  return out
end

local function paint_threads()
  for _, key in ipairs({ "unified", "left", "right" }) do
    local b = state.bufs[key]
    if b and vim.api.nvim_buf_is_valid(b) then vim.api.nvim_buf_clear_namespace(b, ns_threads, 0, -1) end
  end
  state.thread_at, state.thread_rows = {}, {}
  if not state.threads or #state.threads == 0 then return end
  local split = state.bufs.right ~= nil
  -- (path, line, side) → first diff row. Unified rows know their side; split
  -- rows carry one line number per row.
  local by_loc = {}
  for lnum, info in pairs(state.line_map) do
    local side = split and "ANY" or (info.kind == "del" and "LEFT" or "RIGHT")
    local k = (info.path or "") .. "\0" .. tostring(info.line) .. "\0" .. side
    if not by_loc[k] or lnum < by_loc[k] then by_loc[k] = lnum end
  end
  for _, t in ipairs(state.threads) do
    local c = t.root
    if c.line and c.path then
      local side = c.side == "LEFT" and "LEFT" or "RIGHT"
      local lnum = by_loc[c.path .. "\0" .. tostring(c.line) .. "\0" .. (split and "ANY" or side)]
      if lnum then
        if not state.thread_at[lnum] then
          state.thread_at[lnum] = {}
          state.thread_rows[#state.thread_rows + 1] = lnum
        end
        t.side = side
        table.insert(state.thread_at[lnum], t)
      end
    end
  end
  table.sort(state.thread_rows)
  for lnum, list in pairs(state.thread_at) do
    local target = split and (list[1].side == "LEFT" and "left" or "right") or "unified"
    local tw = state.wins[target]
    local width = (tw and vim.api.nvim_win_is_valid(tw)) and vim.api.nvim_win_get_width(tw) or 80
    local vl = {}
    for _, t in ipairs(list) do
      for _, l in ipairs(thread_lines(t, width)) do
        vl[#vl + 1] = { { "  " .. l[1], l[2] } }
      end
    end
    pcall(vim.api.nvim_buf_set_extmark, state.bufs[target], ns_threads, lnum - 1, 0, { virt_lines = vl })
    if split then
      local other = target == "left" and "right" or "left"
      local pad = {}
      for i = 1, #vl do pad[i] = { { " ", "DevOpsDim" } } end
      pcall(vim.api.nvim_buf_set_extmark, state.bufs[other], ns_threads, lnum - 1, 0, { virt_lines = pad })
    end
  end
end

local function load_threads()
  local pr = state.pr
  if not pr then return end
  gh.pr_review_comments(pr.repo, pr.number, function(ok, list)
    if state.pr ~= pr or not ok or type(list) ~= "table" then return end
    table.sort(list, function(a, b) return (a.created_at or "") < (b.created_at or "") end)
    local roots, by_id = {}, {}
    for _, c in ipairs(list) do
      if type(c.in_reply_to_id) ~= "number" then
        by_id[c.id] = { root = c, replies = {} }
        roots[#roots + 1] = by_id[c.id]
      end
    end
    for _, c in ipairs(list) do
      local t = type(c.in_reply_to_id) == "number" and by_id[c.in_reply_to_id]
      if t then t.replies[#t.replies + 1] = c end
    end
    state.threads = roots
    paint_threads()
  end)
end

local function jump_thread(delta)
  local rows = state.thread_rows or {}
  if #rows == 0 then return vim.notify("DevOps: no review threads in this diff", vim.log.levels.INFO) end
  -- Works from the file tree too: act on (and focus) the diff pane.
  local cur_win = vim.api.nvim_get_current_win()
  local focus
  for _, key in ipairs({ "left", "right", "unified" }) do
    if state.wins[key] == cur_win then focus = cur_win end
  end
  if not focus then
    for _, key in ipairs({ "left", "unified" }) do
      local w = state.wins[key]
      if not focus and w and vim.api.nvim_win_is_valid(w) then focus = w end
    end
  end
  if not focus then return end
  local cur = vim.api.nvim_win_get_cursor(focus)[1]
  local target
  if delta > 0 then
    for _, r in ipairs(rows) do if r > cur then target = r break end end
    target = target or rows[1]
  else
    for i = #rows, 1, -1 do if rows[i] < cur then target = rows[i] break end end
    target = target or rows[#rows]
  end
  vim.api.nvim_set_current_win(focus)
  goto_line(target)
end

local function reply_thread()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local list = state.thread_at and state.thread_at[row]
  if not list then
    return vim.notify("DevOps: no review thread on this line (]c / [c to jump to one)", vim.log.levels.INFO)
  end
  local pr = state.pr
  local function reply(t)
    local lines, marks = {}, {}
    for _, l in ipairs(thread_lines(t, 100)) do
      lines[#lines + 1] = l[1]
      marks[#marks + 1] = { #lines - 1, 0, { end_col = #l[1], hl_group = l[2] } }
    end
    table.remove(lines); table.remove(marks) -- drop the key-hint footer
    local where = t.root.path .. ":" .. tostring(t.root.line)
    input.open("Reply on " .. where, "", function(body)
      if body == "" then return end
      gh.pr_review_reply(pr.repo, pr.number, t.root.id, body, function(ok, _, err)
        if not ok then return errors.show("DevOps: reply failed — " .. (err ~= "" and err or "?")) end
        vim.notify("DevOps: replied on " .. where, vim.log.levels.INFO)
        load_threads()
      end)
    end, {
      draft_key = pr.repo .. "#" .. pr.number .. " thread " .. tostring(t.root.id),
      preview = { title = "Thread · " .. where, lines = lines, extmarks = marks, focus = #lines },
    })
  end
  if #list == 1 then return reply(list[1]) end
  vim.ui.select(list, {
    prompt = "Reply to which thread?",
    format_item = function(t)
      return "@" .. (t.root.user and t.root.user.login or "?") .. ": " .. (t.root.body or ""):gsub("\n", " "):sub(1, 60)
    end,
  }, function(t) if t then reply(t) end end)
end

local function show_pending_virt(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns_comments, 0, -1)
  if #state.pending_comments == 0 then return end
  -- Index the diff by (path, line) once, so painting N comments is O(diff + N)
  -- rather than rescanning the whole line_map for every comment.
  local by_loc = {}
  for lnum, info in pairs(state.line_map) do
    local k = (info.path or "") .. "\0" .. tostring(info.line)
    if by_loc[k] == nil or lnum < by_loc[k] then by_loc[k] = lnum end
  end
  local truncate = require("plugins.utils.devops.ui.render").truncate
  for _, c in ipairs(state.pending_comments) do
    local lnum = by_loc[(c.path or "") .. "\0" .. tostring(c.line)]
    if lnum then
      local preview = truncate((c.body or ""):gsub("\n", " "), 60)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_comments, lnum - 1, 0, {
        virt_text = { { "  💬 " .. preview, "DevOpsWarn" } },
        virt_text_pos = "eol",
      })
    end
  end
end

-- Refresh the 💬 markers on every open diff buffer.
local function refresh_virt_all()
  for _, key in ipairs({ "unified", "left", "right" }) do
    local b = state.bufs[key]
    if b and vim.api.nvim_buf_is_valid(b) then show_pending_virt(b) end
  end
  paint_threads()
end

local function add_inline_comment()
  if not state.pr then
    vim.notify("DevOps: no PR context — open diff from a PR", vim.log.levels.WARN)
    return
  end
  local info = get_line_info()
  if not info then
    vim.notify("DevOps: cursor not on a diff line", vim.log.levels.WARN)
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local preview = comment_preview(row, info.path, "Commenting on " .. info.path .. ":" .. info.line)
  input.open("Comment on " .. info.path .. ":" .. info.line, nil, function(body)
    if not body or body:match("^%s*$") then return end
    state.pending_comments[#state.pending_comments + 1] = {
      path = info.path,
      line = info.line,
      body = body,
    }
    save_pending_store()
    vim.notify(string.format("DevOps: comment queued (%d pending)", #state.pending_comments), vim.log.levels.INFO)
    refresh_virt_all()
  end, { preview = preview, draft_key = state.pr
    and (state.pr.repo .. "#" .. state.pr.number .. " " .. info.path .. ":" .. info.line) or nil })
end

-- Rows r1..r2 (1-based) → the new-side range a suggestion replaces:
-- { path, start_line, line, lines }, or nil + reason.
function M.suggestion_range(line_map, r1, r2)
  if r1 > r2 then r1, r2 = r2, r1 end
  local path, first, last, lines
  for r = r1, r2 do
    local m = line_map[r]
    if m and m.new then
      if path and m.path ~= path then return nil, "the selection spans two files" end
      if last and m.line ~= last + 1 then return nil, "the selection isn't contiguous on the new side" end
      path = m.path
      first = first or m.line
      last = m.line
      lines = lines or {}
      lines[#lines + 1] = m.text or ""
    end
  end
  if not path then return nil, "select added or unchanged lines (new side)" end
  return { path = path, start_line = first ~= last and first or nil, line = last, lines = lines }
end

-- Body template: the selected lines inside a ```suggestion block, to edit.
function M.suggestion_body(lines)
  return "```suggestion\n" .. table.concat(lines, "\n") .. "\n```"
end

local function add_suggestion(r1, r2)
  if not state.pr then
    return vim.notify("DevOps: no PR context — open diff from a PR", vim.log.levels.WARN)
  end
  if state.wins.left and vim.api.nvim_get_current_win() == state.wins.left then
    return vim.notify("DevOps: suggest from the new side (right pane)", vim.log.levels.INFO)
  end
  local rng, why = M.suggestion_range(state.line_map, r1, r2)
  if not rng then return vim.notify("DevOps: " .. why, vim.log.levels.INFO) end
  local where = rng.path .. ":" .. (rng.start_line and (rng.start_line .. "-") or "") .. rng.line
  local preview = comment_preview(math.min(r1, r2), rng.path, "Suggesting on " .. where)
  input.open("Suggestion on " .. where, M.suggestion_body(rng.lines), function(body)
    if not body or body:match("^%s*$") then return end
    state.pending_comments[#state.pending_comments + 1] = {
      path = rng.path, line = rng.line, start_line = rng.start_line, body = body,
    }
    save_pending_store()
    vim.notify(string.format("DevOps: suggestion queued (%d pending)", #state.pending_comments), vim.log.levels.INFO)
    refresh_virt_all()
  end, { preview = preview, draft_key = false })
end

-- Read-only preview of the inline comments a review will send.
function M._review_summary(pending)
  if not pending or #pending == 0 then return nil end
  local lines = {}
  for _, c in ipairs(pending) do
    local where = c.path .. ":" .. (c.start_line and (c.start_line .. "-") or "") .. c.line
    local first = (c.body or ""):match("^[^\n]*") or ""
    if (c.body or ""):find("```suggestion", 1, true) then first = "✎ suggestion" end
    lines[#lines + 1] = "  💬 " .. where .. "  " .. first
  end
  return { title = " " .. #pending .. " inline comment" .. (#pending == 1 and "" or "s") .. " ", lines = lines, wrap = false }
end

local function submit_review()
  if not state.pr then
    vim.notify("DevOps: no PR context — open diff from a PR", vim.log.levels.WARN)
    return
  end
  local own = gh.is_me(state.pr_author)
  local items = { "Comment — Submit general feedback" }
  if not own then
    items[2] = "Approve — Approve merging these changes"
    items[3] = "Request changes — Suggest changes before merging"
  end
  local n_pending = #state.pending_comments
  local prompt = n_pending > 0
    and ("Submit review (" .. n_pending .. " inline comment" .. (n_pending == 1 and "" or "s") .. "):")
    or "Submit review:"
  if own then prompt = prompt:gsub(":$", " — your PR, comment only:") end
  vim.ui.select(items, { prompt = prompt }, function(choice)
    if not choice then return end
    local event = choice:match("^Approve") and "APPROVE"
      or choice:match("^Request") and "REQUEST_CHANGES"
      or "COMMENT"
    local pending = state.pending_comments
    local function do_submit(body)
      gh.pr_review(state.pr.repo, state.pr.number, event, body, pending, function(ok, _, err)
        if not ok then
          return errors.show("DevOps: review failed — " .. (err or "unknown"))
        end
        local n_inline = #pending
        for i = #pending, 1, -1 do pending[i] = nil end -- clear in place (keeps the persisted ref)
        save_pending_store()
        local label = event == "APPROVE" and "approved"
          or event == "REQUEST_CHANGES" and "changes requested"
          or "commented"
        local count = n_inline > 0 and string.format(" (%d inline comments)", n_inline) or ""
        vim.notify("DevOps: review submitted — " .. label .. count, vim.log.levels.INFO)
        refresh_virt_all() -- drop the 💬 markers for the comments we just sent
      end)
    end
    if event == "APPROVE" and #pending == 0 then
      do_submit("")
    else
      input.open("Review body (" .. event:lower():gsub("_", " ") .. ")", nil, function(body)
        do_submit(body or "")
      end, { preview = M._review_summary(pending) })
    end
  end)
end

-- Move the diff to a queued comment's file:line.
local function jump_to_comment(c)
  for bl, info in pairs(state.line_map) do
    if info.path == c.path and info.line == c.line then
      local w = state.wins.right or state.wins.unified or state.wins.left
      if w and vim.api.nvim_win_is_valid(w) then
        vim.api.nvim_set_current_win(w)
        goto_line(bl)
      end
      return
    end
  end
  vim.notify("DevOps: that line isn't in the current diff", vim.log.levels.WARN)
end

-- Panel listing the queued review comments: ↵ jump · e edit · dd delete · S submit.
local function open_pending_panel()
  if not state.pr then
    vim.notify("DevOps: no PR context — open the diff from a PR", vim.log.levels.WARN)
    return
  end
  local pending = state.pending_comments
  if not pending or #pending == 0 then
    vim.notify("DevOps: no pending review comments (add with 'c')", vim.log.levels.INFO)
    return
  end
  local buf = make_buf()
  local win
  local rows = {}
  local function rerender()
    local lines, hls = {}, {}
    local hdr = "  Pending review (" .. #pending .. ")"
    lines[1], lines[2] = hdr, ""
    hls[#hls + 1] = { 0, 0, #hdr, "DevOpsTitle" }
    rows = {}
    for i, c in ipairs(pending) do
      local name = (c.path or "?"):match("[^/]+$") or c.path or "?"
      local loc = ("  %s:%d"):format(name, type(c.line) == "number" and c.line or 0)
      local prev = render.truncate(((c.body or ""):gsub("%s+", " ")), 54)
      lines[#lines + 1] = loc .. "   " .. prev
      hls[#hls + 1] = { #lines - 1, 0, #loc, "DevOpsId" }
      rows[#lines] = i
    end
    local help = "  ↵ jump   e edit   dd delete   S submit   q close"
    lines[#lines + 1], lines[#lines + 2] = "", help
    hls[#hls + 1] = { #lines - 1, 0, #help, "DevOpsDim" }
    set_lines(buf, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(hls) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
    end
  end
  rerender()
  local w = math.min(74, vim.o.columns - 8)
  local ht = math.min(#pending + 5, math.max(8, vim.o.lines - 6))
  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = ht,
    row = math.floor((vim.o.lines - ht) / 2), col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded",
    title = " Pending review comments ", title_pos = "center",
  })
  vim.wo[win].cursorline = true
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"
  pcall(vim.api.nvim_win_set_cursor, win, { 3, 0 })

  local function cur() return rows[vim.api.nvim_win_get_cursor(win)[1]] end
  local function close_panel()
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function map(k, fn) vim.keymap.set("n", k, fn, { buffer = buf, nowait = true, silent = true }) end

  map("<CR>", function()
    local i = cur(); if not i then return end
    close_panel()
    jump_to_comment(pending[i])
  end)
  map("e", function()
    local i = cur(); if not i then return end
    local c = pending[i]
    input.open("Edit comment on " .. c.path .. ":" .. c.line, c.body, function(nb)
      if nb and not nb:match("^%s*$") then c.body = nb; save_pending_store(); refresh_virt_all() end
      if win and vim.api.nvim_win_is_valid(win) then rerender() end
    end, { preview = pending_preview(c) })
  end)
  map("dd", function()
    local i = cur(); if not i then return end
    table.remove(pending, i)
    save_pending_store(); refresh_virt_all()
    if #pending == 0 then close_panel(); return end
    rerender()
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(2 + i, 2 + #pending), 0 })
  end)
  map("S", function() close_panel(); submit_review() end)
  map("q", close_panel)
  map("<C-d>", close_panel)
  map("<Esc>", close_panel)
end

local function toggle_blame()
  state.blame_visible = not state.blame_visible
  for _, key in ipairs({ "unified", "left", "right" }) do
    local b = state.bufs[key]
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_clear_namespace(b, ns_blame, 0, -1)
    end
  end
  if not state.blame_visible then
    vim.notify("DevOps: blame off", vim.log.levels.INFO)
    return
  end
  if not state.pr then
    vim.notify("DevOps: no PR context for blame", vim.log.levels.WARN)
    state.blame_visible = false
    return
  end
  local paths = {}
  local seen = {}
  for _, info in pairs(state.line_map) do
    if info.path and not seen[info.path] then
      seen[info.path] = true
      paths[#paths + 1] = info.path
    end
  end
  local remaining, failed = #paths, 0
  if remaining == 0 then
    vim.notify("DevOps: no files to blame", vim.log.levels.INFO)
    state.blame_visible = false
    return
  end
  for _, fpath in ipairs(paths) do
    local cmd = { "git", "blame", "--porcelain", fpath }
    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        if res.code == 0 and res.stdout then
          local blame = {}
          local current_line
          for line in res.stdout:gmatch("[^\n]+") do
            local hash, ln = line:match("^(%x+)%s+%d+%s+(%d+)")
            if hash then
              current_line = tonumber(ln)
            end
            local author = line:match("^author%s+(.+)")
            if author and current_line then
              blame[current_line] = author
            end
            local time = line:match("^author%-time%s+(%d+)")
            if time and current_line and blame[current_line] then
              local ago = os.difftime(os.time(), tonumber(time))
              local label
              if ago < 3600 then label = math.floor(ago / 60) .. "m"
              elseif ago < 86400 then label = math.floor(ago / 3600) .. "h"
              elseif ago < 2592000 then label = math.floor(ago / 86400) .. "d"
              else label = math.floor(ago / 2592000) .. "mo" end
              blame[current_line] = blame[current_line] .. " " .. label
            end
          end
          state.blame_data[fpath] = blame
        else
          failed = failed + 1 -- git blame couldn't read this file (not in the working tree)
        end
        remaining = remaining - 1
        if remaining == 0 and state.blame_visible then
          local applied = 0
          for lnum, info in pairs(state.line_map) do
            local bd = state.blame_data[info.path]
            if bd and bd[info.line] then
              applied = applied + 1
              for _, key in ipairs({ "unified", "left", "right" }) do
                local b = state.bufs[key]
                if b and vim.api.nvim_buf_is_valid(b) then
                  pcall(vim.api.nvim_buf_set_extmark, b, ns_blame, lnum - 1, 0, {
                    virt_text = { { "  " .. bd[info.line], "DevOpsDim" } },
                    virt_text_pos = "eol",
                  })
                end
              end
            end
          end
          if applied == 0 then
            state.blame_visible = false
            vim.notify(
              "DevOps: blame unavailable — git blame found no matching lines.\n"
                .. "Check out the PR branch ('x') and open Neovim from the repo dir.",
              vim.log.levels.WARN)
          else
            vim.notify("DevOps: blame on", vim.log.levels.INFO)
          end
        end
      end)
    end)
  end
end

local function setup_keymaps(buf)
  map_buf(buf, "q", close, "Close diff")
  map_buf(buf, "<C-d>", close, "Close diff")
  map_buf(buf, "<Esc>", close, "Close diff")
  map_buf(buf, "<Tab>", function()
    state.mode = state.mode == "unified" and "split" or "unified"
    M.open(state.diff_text, state.title)
  end, "Toggle diff mode")
  map_buf(buf, "T", function() render.pick_diff_theme() end, "Pick diff theme")
  map_buf(buf, "B", toggle_blame, "Toggle blame")
  map_buf(buf, "f", function() toggle_tree() end, "Toggle file tree")
  map_pane_nav(buf)
  map_buf(buf, "]f", function() jump_file(1) end, "Next file")
  map_buf(buf, "[f", function() jump_file(-1) end, "Prev file")
  map_buf(buf, "gg", function() show_page(state.page or 1, "top") end, "Top of file")
  map_buf(buf, "G", function() show_page(state.page or 1, "bottom") end, "Bottom of file")
  vim.api.nvim_create_autocmd("CursorMoved", { group = augroup, buffer = buf, callback = on_diff_cursor })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = augroup,
    callback = function()
      for id in pairs(vim.v.event or {}) do
        local w = tonumber(id)
        if w and vim.api.nvim_win_get_buf(w) == buf then return on_diff_scroll() end
      end
    end,
  })
  -- Open in browser at current file/line position
  if state.pr then
    map_buf(buf, "o", function()
      local info = get_line_info()
      local base = "https://github.com/" .. state.pr.repo .. "/pull/" .. state.pr.number .. "/files"
      if info and info.path then
        local hash = vim.fn.sha256(info.path)
        vim.ui.open(base .. "#diff-" .. hash .. "R" .. info.line)
      else
        vim.ui.open(base)
      end
    end, "Open in browser")
  end
  -- Review keymaps (only active when PR context exists)
  if state.pr then
    map_buf(buf, "c", add_inline_comment, "Inline comment")
    map_buf(buf, "s", function()
      local r = vim.api.nvim_win_get_cursor(0)[1]
      add_suggestion(r, r)
    end, "Suggest a change (line)")
    vim.keymap.set("x", "s", function()
      local r1, r2 = vim.fn.line("v"), vim.fn.line(".")
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
      add_suggestion(r1, r2)
    end, { buffer = buf, nowait = true, silent = true, desc = "Suggest a change (selection)" })
    map_buf(buf, "gc", open_pending_panel, "Pending review comments")
    map_buf(buf, "x", function() toggle_viewed(nil, true) end, "Toggle file viewed")
    map_buf(buf, "S", submit_review, "Submit review")
    map_buf(buf, "r", reply_thread, "Reply to review thread")
    map_buf(buf, "]c", function() jump_thread(1) end, "Next review thread")
    map_buf(buf, "[c", function() jump_thread(-1) end, "Prev review thread")
  end
end

---------------------------------------------------------------------------
-- Parse
---------------------------------------------------------------------------

local function parse_diff(diff_text)
  local files, current_file, current_hunk = {}, nil, nil
  local function push_file()
    if current_file then
      if current_hunk then
        current_file.hunks[#current_file.hunks + 1] = current_hunk
      end
      files[#files + 1] = current_file
    end
    current_file, current_hunk = nil, nil
  end

  for _, line in ipairs(vim.split(diff_text or "", "\n", { plain = true })) do
    if line:match("^diff %-%-git ") then
      push_file()
      local old_path, new_path = line:match("^diff %-%-git a/(.-) b/(.-)$")
      current_file = {
        title = new_path or old_path or line,
        old_path = old_path,
        new_path = new_path,
        headers = { line },
        hunks = {},
      }
    else
      current_file = current_file or { title = "diff", headers = {}, hunks = {} }
      if line:match("^@@") then
        if current_hunk then current_file.hunks[#current_file.hunks + 1] = current_hunk end
        current_hunk = { header = line, lines = {} }
      elseif current_hunk then
        current_hunk.lines[#current_hunk.lines + 1] = line
      else
        current_file.headers[#current_file.headers + 1] = line
        local old_path = line:match("^%-%-%- a/(.+)$")
        local new_path = line:match("^%+%+%+ b/(.+)$")
        if old_path then current_file.old_path = old_path end
        if new_path then
          current_file.new_path = new_path
          current_file.title = new_path
        end
      end
    end
  end
  push_file()
  return files
end

---------------------------------------------------------------------------
-- Line number gutter
---------------------------------------------------------------------------

local GUTTER_W = 5 -- "1234 │ " = 5+3+1 = 9 visible chars (but │ is 3 bytes)
local GUTTER_SEP = " │ "

local function gutter(num)
  if not num then return string.rep(" ", GUTTER_W) .. GUTTER_SEP end
  local s = tostring(num)
  return string.rep(" ", GUTTER_W - #s) .. s .. GUTTER_SEP
end

local function gutter_bytes()
  return GUTTER_W + #GUTTER_SEP
end

local function parse_hunk_header(header)
  local old_start, new_start = header:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
  return tonumber(old_start), tonumber(new_start)
end

---------------------------------------------------------------------------
-- Highlight application (shared between unified and split)
---------------------------------------------------------------------------

local function apply_marks(buf, marks)
  for _, m in ipairs(marks) do
    if m.type == "file" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffFileHdr" })
    elseif m.type == "hunk" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffHunkHdr" })
    elseif m.type == "add" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffAdd" })
    elseif m.type == "del" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffDel" })
    elseif m.type == "empty" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffEmpty" })
    elseif m.type == "ctx" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffCtx" })
    elseif m.type == "sep" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffSep" })
    elseif m.type == "filegap" then
      vim.api.nvim_buf_set_extmark(buf, ns, m.line, 0, { line_hl_group = "DevOpsDiffFileGap" })
    end
    -- Line number gutter highlight
    if m.gutter_end then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line, 0, {
        end_col = m.gutter_end, hl_group = "DevOpsDiffLineNr",
      })
    end
  end
end

---------------------------------------------------------------------------
-- Footer
---------------------------------------------------------------------------

local function render_footer(total_width, footer_row)
  local buf = make_buf()
  state.bufs.footer = buf

  local mode_label = state.mode == "unified" and "UNIFIED" or " SPLIT "
  local sep = "  " .. string.char(0xe2, 0x94, 0x82) .. "  "
  local parts = {
    { "  " .. mode_label, "DevOpsDiffFileHdr" },
    { "   Tab ", "DevOpsKey" }, { "toggle", "DevOpsAction" },
    { sep, nil },
    { "]f ", "DevOpsKey" }, { "[f ", "DevOpsKey" }, { "file", "DevOpsAction" },
  }
  if state.pr then
    local pending = #state.pending_comments
    local badge = pending > 0 and (" (" .. pending .. ")") or ""
    vim.list_extend(parts, {
      { sep, nil },
      { "c ", "DevOpsKey" }, { "comment", "DevOpsAction" },
      { "  ", nil },
      { "s ", "DevOpsKey" }, { "suggest", "DevOpsAction" },
      { "  ", nil },
      { "gc ", "DevOpsKey" }, { "list" .. badge, "DevOpsAction" },
      { "  ", nil },
      { "S ", "DevOpsKey" }, { "submit review", "DevOpsAction" },
      { "  ", nil },
      { "x ", "DevOpsKey" }, { "viewed", "DevOpsAction" },
      { "  ", nil },
      { "]c ", "DevOpsKey" }, { "[c ", "DevOpsKey" }, { "r ", "DevOpsKey" }, { "threads", "DevOpsAction" },
    })
  end
  vim.list_extend(parts, {
    { sep, nil },
    { "T ", "DevOpsKey" }, { "theme", "DevOpsAction" },
    { "  ", nil },
    { "B ", "DevOpsKey" }, { "blame", "DevOpsAction" },
    { "  ", nil },
    { "f ", "DevOpsKey" }, { "tree", "DevOpsAction" },
    { "  ", nil },
    { "S-←→ ", "DevOpsKey" }, { "pane", "DevOpsAction" },
    { sep, nil },
    { "q ", "DevOpsKey" }, { "close", "DevOpsAction" },
  })

  local text, hl_ranges = "", {}
  for _, p in ipairs(parts) do
    local start = #text
    text = text .. p[1]
    if p[2] then
      hl_ranges[#hl_ranges + 1] = { start, #text, p[2] }
    end
  end

  set_lines(buf, { text })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = total_width,
    height = 1,
    row = footer_row,
    col = 0,
    style = "minimal",
    border = "none",
    focusable = false,
  })
  state.wins.footer = win
  vim.wo[win].winhighlight = "Normal:DevOpsDiffBar"

  for _, r in ipairs(hl_ranges) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, r[1], {
      end_col = r[2], hl_group = r[3],
    })
  end
end

---------------------------------------------------------------------------
-- Unified
---------------------------------------------------------------------------

-- Build the unified-diff lines + highlight marks for a parsed file list.
-- Pure: returns (lines, marks, file_positions, line_map) so the same styling
-- renders into either the full-screen float or a plain side split.
local function build_unified(files, total_w)
  local lines, marks = {}, {}
  local file_positions = {}
  local line_map = {}

  for fi, file in ipairs(files) do
    if fi > 1 then
      -- 3 dark blank lines to separate files.
      for _ = 1, 3 do
        lines[#lines + 1] = ""
        marks[#marks + 1] = { line = #lines - 1, type = "filegap" }
      end
    end
    do -- 2 rules above the header (matching the 2 below)
      local rule = sep_rule(total_w)
      for _ = 1, 2 do
        lines[#lines + 1] = rule
        marks[#marks + 1] = { line = #lines - 1, type = "sep" }
      end
    end
    local title = file.new_path or file.old_path or "unknown"
    local fpath = file.new_path or file.old_path or ""

    file_positions[#file_positions + 1] = #lines
    lines[#lines + 1] = file_separator(title, total_w)
    marks[#marks + 1] = { line = #lines - 1, type = "file" }
    do
      local rule = sep_rule(total_w)
      lines[#lines + 1] = rule
      marks[#marks + 1] = { line = #lines - 1, type = "sep" }
      lines[#lines + 1] = rule
      marks[#marks + 1] = { line = #lines - 1, type = "sep" }
    end

    for hi, hunk in ipairs(file.hunks or {}) do
      if hi > 1 then lines[#lines + 1] = "" end

      local old_ln, new_ln = parse_hunk_header(hunk.header)
      old_ln = old_ln or 1
      new_ln = new_ln or 1

      for _, ln in ipairs(hunk.lines or {}) do
        local prefix = ln:sub(1, 1)
        local content = ln:sub(2)
        local g = gutter_bytes()
        if prefix == "+" then
          lines[#lines + 1] = gutter(new_ln) .. content
          marks[#marks + 1] = { line = #lines - 1, type = "add", gutter_end = g }
          line_map[#lines] = { path = fpath, line = new_ln, kind = "add", new = true, text = content }
          new_ln = new_ln + 1
        elseif prefix == "-" then
          lines[#lines + 1] = gutter(old_ln) .. content
          marks[#marks + 1] = { line = #lines - 1, type = "del", gutter_end = g }
          line_map[#lines] = { path = fpath, line = old_ln, kind = "del" }
          old_ln = old_ln + 1
        elseif prefix == " " then
          lines[#lines + 1] = gutter(new_ln) .. content
          marks[#marks + 1] = { line = #lines - 1, type = "ctx", gutter_end = g }
          line_map[#lines] = { path = fpath, line = new_ln, kind = "ctx", new = true, text = content }
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        else
          lines[#lines + 1] = gutter(nil) .. ln
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        end
      end
    end
  end

  if #lines == 0 then lines = { "  No changes" } end
  return lines, marks, file_positions, line_map
end

-- Pane title: the current file's path (trimmed from the left to fit) · side.
local function pane_title(win, side, base)
  pcall(function()
    local path = state.page and file_name(state.page) or ""
    local room = vim.api.nvim_win_get_width(win) - #side - 9
    local cfg = vim.api.nvim_win_get_config(win)
    local seen = state.page and state.viewed[file_name(state.page)]
    if seen then room = room - 4 end
    if vim.fn.strdisplaywidth(path) > room then
      path = "…" .. vim.fn.strcharpart(path, vim.fn.strchars(path) - math.max(1, room - 1))
    end
    if path ~= "" then
      cfg.title = { { " " .. path, "DevOpsTitle" } }
      if seen then cfg.title[#cfg.title + 1] = { " ✓", "DevOpsOk" } end
      cfg.title[#cfg.title + 1] = { " · " .. side .. " ", "DevOpsDim" }
    else
      cfg.title = " " .. base .. " · " .. side .. " "
    end
    cfg.title_pos = "center"
    vim.api.nvim_win_set_config(win, cfg)
  end)
end

local function render_unified()
  close_windows()
  local files = state.parsed or {}

  local off = tree_off()
  local total_w = vim.o.columns - 2 - off
  local total_h = vim.o.lines - 4

  local lines, marks, file_positions, line_map = build_unified(files, total_w)
  state.file_positions = file_positions
  state.line_map = line_map

  local buf = make_buf()
  state.bufs.unified = buf
  set_lines(buf, lines)
  apply_marks(buf, marks)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = total_w,
    height = total_h,
    row = 0,
    col = off,
    style = "minimal",
    border = "rounded",
    title = " " .. (state.title ~= "" and state.title or "Diff") .. " · unified ",
    title_pos = "center",
  })
  state.wins.unified = win
  set_win_opts(win)
  setup_keymaps(buf)
  local base = state.title ~= "" and state.title or "Diff"
  state.on_page = function() pane_title(win, "unified", base) end
  render_footer(total_w, total_h + 2)
  show_page(state.page or 1, "top")
  render_tree_pane(total_h)
end

---------------------------------------------------------------------------
-- Split
---------------------------------------------------------------------------

-- "new" / "deleted" / nil, from the git headers.
local function file_kind(file)
  for _, h in ipairs(file.headers or {}) do
    if h:match("^new file mode") or h == "--- /dev/null" then return "new" end
    if h:match("^deleted file mode") or h == "+++ /dev/null" then return "deleted" end
  end
end

local ns_placeholder = vim.api.nvim_create_namespace("DevOpsDiffPlaceholder")

local function build_split_data(files, pane_width)
  local left, right = {}, {}
  local left_marks, right_marks = {}, {}
  local file_pos = {}
  local line_map = {}
  local placeholders = {} -- { side = "left"|"right", line = 0-based, text }

  local function add(fpath, lhs, rhs, ltype, rtype, map_line, text, is_new)
    left[#left + 1] = lhs or ""
    right[#right + 1] = rhs or ""
    if ltype then left_marks[#left_marks + 1] = { line = #left - 1, type = ltype } end
    if rtype then right_marks[#right_marks + 1] = { line = #right - 1, type = rtype } end
    if map_line and fpath then
      line_map[#right] = { path = fpath, line = map_line, new = is_new, text = text }
    end
  end

  for fi, file in ipairs(files) do
    if fi > 1 then
      -- 3 dark blank lines to separate files.
      add(nil, "", "", "filegap", "filegap")
      add(nil, "", "", "filegap", "filegap")
      add(nil, "", "", "filegap", "filegap")
    end
    do -- 2 rules above the header (matching the 2 below)
      local rule = sep_rule(pane_width)
      add(nil, rule, rule, "sep", "sep")
      add(nil, rule, rule, "sep", "sep")
    end
    local title = file.new_path or file.old_path or "unknown"
    local fpath = file.new_path or file.old_path or ""
    file_pos[#file_pos + 1] = #left
    local sep_line = file_separator(title, pane_width)
    add(nil, sep_line, sep_line, "file", "file")
    do
      local rule = sep_rule(pane_width)
      add(nil, rule, rule, "sep", "sep")
      add(nil, rule, rule, "sep", "sep")
    end
    local kind = file_kind(file)
    if kind == "new" then
      placeholders[#placeholders + 1] = { side = "left", line = #left, text = "new file · no previous version" }
    elseif kind == "deleted" then
      placeholders[#placeholders + 1] = { side = "right", line = #right, text = "file deleted" }
    end

    for hi, hunk in ipairs(file.hunks or {}) do
      if hi > 1 then add(nil, "", "") end
      local removed, added = {}, {}
      local old_ln, new_ln = parse_hunk_header(hunk.header)
      old_ln = old_ln or 1
      new_ln = new_ln or 1
      local g = gutter_bytes()

      local function flush()
        if #removed == 0 and #added == 0 then return end
        local total = math.max(#removed, #added)
        for i = 1, total do
          local l = removed[i]
          local r = added[i]
          local l_ln = l and old_ln + i - 1 or nil
          local r_ln = r and new_ln + i - 1 or nil
          add(fpath,
            l and (gutter(l_ln) .. l) or "",
            r and (gutter(r_ln) .. r) or "",
            l and "del" or "empty",
            r and "add" or "empty",
            r_ln or l_ln,
            r or l,
            r ~= nil
          )
          if l then left_marks[#left_marks].gutter_end = g end
          if r then right_marks[#right_marks].gutter_end = g end
        end
        old_ln = old_ln + #removed
        new_ln = new_ln + #added
        removed, added = {}, {}
      end

      for _, ln in ipairs(hunk.lines or {}) do
        local prefix = ln:sub(1, 1)
        local content = ln:sub(2)
        if prefix == "-" then
          removed[#removed + 1] = content
        elseif prefix == "+" then
          added[#added + 1] = content
        elseif prefix == " " then
          flush()
          add(fpath, gutter(old_ln) .. content, gutter(new_ln) .. content, "ctx", "ctx", new_ln, content, true)
          left_marks[#left_marks].gutter_end = g
          right_marks[#right_marks].gutter_end = g
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        else
          flush()
          add(nil, gutter(nil) .. ln, gutter(nil) .. ln)
          old_ln = old_ln + 1
          new_ln = new_ln + 1
        end
      end
      flush()
    end
  end

  return left, right, left_marks, right_marks, file_pos, line_map, placeholders
end

local function render_split()
  close_windows()
  local files = state.parsed or {}
  local off = tree_off()
  local total_w = vim.o.columns - 4 - off
  local left_w = math.floor(total_w / 2)
  local left_lines, right_lines, left_marks, right_marks, file_pos, line_map, placeholders = build_split_data(files, left_w)
  state.file_positions = file_pos
  state.line_map = line_map
  local right_w = total_w - left_w
  local total_h = vim.o.lines - 4

  local left_buf, right_buf = make_buf(), make_buf()
  state.bufs.left, state.bufs.right = left_buf, right_buf
  set_lines(left_buf, left_lines)
  set_lines(right_buf, right_lines)
  apply_marks(left_buf, left_marks)
  apply_marks(right_buf, right_marks)
  for _, ph in ipairs(placeholders) do
    pcall(vim.api.nvim_buf_set_extmark, ph.side == "left" and left_buf or right_buf, ns_placeholder, ph.line, 0, {
      virt_text = { { "  ∅  " .. ph.text, "DevOpsDim" } }, virt_text_pos = "overlay",
    })
  end

  local base = state.title ~= "" and state.title or "Diff"
  local left_win = vim.api.nvim_open_win(left_buf, true, {
    relative = "editor",
    width = left_w, height = total_h, row = 0, col = off,
    style = "minimal", border = "rounded",
    title = " " .. base .. " · old ", title_pos = "center",
  })
  local right_win = vim.api.nvim_open_win(right_buf, false, {
    relative = "editor",
    width = right_w, height = total_h, row = 0, col = off + left_w + 2,
    style = "minimal", border = "rounded",
    title = " " .. base .. " · new ", title_pos = "center",
  })
  state.wins.left, state.wins.right = left_win, right_win
  set_win_opts(left_win)
  set_win_opts(right_win)

  for _, win in ipairs({ left_win, right_win }) do
    vim.wo[win].scrollbind = true
    vim.wo[win].cursorbind = true
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    setup_keymaps(buf)
  end

  local function update_titles()
    pane_title(left_win, "old", base)
    pane_title(right_win, "new", base)
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup, buffer = buf, callback = update_titles,
    })
  end
  state.on_page = update_titles
  render_footer(vim.o.columns - 2, total_h + 2)
  show_page(state.page or 1, "top")
  render_tree_pane(total_h)
end

---------------------------------------------------------------------------
-- File-tree pane (left) — a snacks-explorer-style nested tree of the changed
-- files: directory nodes (▾/▸ expand/collapse) + file icons. Moving onto a file
-- (or ↵) jumps the diff to that file. The diff itself is unchanged.
---------------------------------------------------------------------------

render_tree_pane = function(total_h)
  if not state.tree_visible then return end
  local files = state.parsed or {}
  if #files == 0 then return end
  state.tree_collapsed = state.tree_collapsed or {}
  local ok_dev, devicons = pcall(require, "nvim-web-devicons")
  local function file_icon(name)
    if ok_dev and devicons then
      local ic, hl = devicons.get_icon(name, name:match("%.([%w_]+)$"), { default = true })
      return ic or "", hl or "DevOpsId"
    end
    return "", "DevOpsId"
  end

  -- Build a nested directory tree from the file paths.
  local root = { dirs = {}, dorder = {}, files = {}, path = "" }
  for i, f in ipairs(files) do
    local path = f.new_path or f.old_path or "?"
    local parts = vim.split(path, "/", { plain = true })
    local node = root
    for d = 1, #parts - 1 do
      local seg = parts[d]
      if not node.dirs[seg] then
        local full = node.path == "" and seg or (node.path .. "/" .. seg)
        node.dirs[seg] = { name = seg, path = full, dirs = {}, dorder = {}, files = {} }
        node.dorder[#node.dorder + 1] = seg
      end
      node = node.dirs[seg]
    end
    node.files[#node.files + 1] = { name = parts[#parts], idx = i, path = path }
  end

  local buf = make_buf()
  state.bufs.tree = buf
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", width = TREE_W, height = total_h, row = 0, col = 0,
    style = "minimal", border = "rounded", title = " files ", title_pos = "center",
  })
  state.wins.tree = win
  set_win_opts(win)
  vim.wo[win].cursorline = true
  -- New windows inherit window-local options from the window they're opened in,
  -- and the split panes set these — which would bind the tree to the diff
  -- (scrolls off-screen, cursor yoked). Unbind so the tree is independent.
  vim.wo[win].scrollbind = false
  vim.wo[win].cursorbind = false
  -- Match the rest of the plugin (the dashboard panes use Normal, not the dimmer
  -- NormalFloat; default cursorline) so the tree's background is consistent.
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"

  -- rows[line] = { dir=true, path=… } | { dir=false, idx=…, path=… }
  local rows = {}
  local function rebuild()
    local lines, hls = {}, {}
    rows = {}
    local function emit(text, segs)
      lines[#lines + 1] = text
      for _, sg in ipairs(segs or {}) do
        hls[#hls + 1] = { l = #lines - 1, s = sg[1], e = sg[2], g = sg[3] }
      end
    end
    local n_seen = 0
    for _, f in ipairs(files) do if state.viewed[f.new_path or f.old_path or ""] then n_seen = n_seen + 1 end end
    local header = "  Changed files (" .. #files .. ")" .. (n_seen > 0 and ("  ✓ " .. n_seen) or "")
    emit(header, { { 0, #header, "DevOpsTitle" } })
    emit("", {})
    local function walk(node, depth)
      table.sort(node.dorder)
      for _, seg in ipairs(node.dorder) do
        local d = node.dirs[seg]
        local indent = string.rep("  ", depth)
        local arrow = state.tree_collapsed[d.path] and "▸" or "▾"
        local text = indent .. arrow .. " " .. render.truncate(d.name, TREE_W - #indent - 4)
        emit(text, { { #indent, #text, "Directory" } })
        rows[#lines] = { dir = true, path = d.path }
        if not state.tree_collapsed[d.path] then walk(d, depth + 1) end
      end
      table.sort(node.files, function(a, b) return a.name < b.name end)
      for _, fl in ipairs(node.files) do
        local indent = string.rep("  ", depth)
        local ic, ihl = file_icon(fl.name)
        local seen = state.viewed[fl.path]
        local mark = seen and "✓" or " "
        local text = indent .. mark .. " " .. ic .. " " .. render.truncate(fl.name, TREE_W - #indent - 4)
        local istart = #indent + #mark + 1
        emit(text, {
          { #indent, #indent + #mark, "DevOpsOk" },
          { istart, istart + #ic, seen and "DevOpsDim" or ihl },
          { istart + #ic + 1, #text, seen and "DevOpsDim" or "Normal" },
        })
        rows[#lines] = { dir = false, idx = fl.idx, path = fl.path }
      end
    end
    walk(root, 0)
    set_lines(buf, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(hls) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.l, h.s, { end_col = h.e, hl_group = h.g })
    end
  end

  local function current() return rows[vim.api.nvim_win_get_cursor(win)[1]] end

  -- Move every diff pane to file `idx` (programmatic cursor sets don't trigger
  -- scrollbind, so set all of them).
  -- Show the file under the cursor as the page, header at the top. `force`
  -- re-shows the current file too (↵ / l); plain cursor moves skip it so
  -- re-entering the tree doesn't reset the diff's scroll position.
  local function jump(force)
    local r = current()
    if not r or r.dir then return end
    if not force and r.idx == state.page then return end
    show_page(r.idx, "top")
  end
  local function focus_diff()
    for _, key in ipairs({ "left", "unified" }) do
      local w = state.wins[key]
      if w and vim.api.nvim_win_is_valid(w) then vim.api.nvim_set_current_win(w) return end
    end
  end
  local function goto_path(path, want_dir)
    for line, r in pairs(rows) do
      if r.path == path and (r.dir == want_dir) then
        pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
        return true
      end
    end
  end
  local function set_collapsed(path, val)
    state.tree_collapsed[path] = val or nil
    rebuild()
    goto_path(path, true)
  end

  map_buf(buf, "q", close, "Close diff")
  map_buf(buf, "<C-d>", close, "Close diff")
  map_buf(buf, "<Esc>", close, "Close diff")
  map_buf(buf, "f", function() toggle_tree() end, "Toggle file tree")
  -- Themes only redefine highlight groups, so they preview live without a
  -- re-render (which would reset the tree cursor and focus).
  map_buf(buf, "T", function() render.pick_diff_theme() end, "Pick diff theme")
  if state.pr then
    map_buf(buf, "]c", function() jump_thread(1) end, "Next review thread")
    map_buf(buf, "[c", function() jump_thread(-1) end, "Prev review thread")
  end
  map_pane_nav(buf)
  if state.pr then
    map_buf(buf, "x", function()
      local r = current()
      if r and not r.dir then toggle_viewed(r.idx, false) end
    end, "Toggle viewed")
  end
  map_buf(buf, "<CR>", function()
    local r = current()
    if not r then return end
    if r.dir then set_collapsed(r.path, not state.tree_collapsed[r.path])
    else jump(true) focus_diff() end
  end, "Open file / toggle dir")
  map_buf(buf, "l", function()
    local r = current()
    if not r then return end
    if r.dir then set_collapsed(r.path, false)
    else jump(true) focus_diff() end
  end, "Expand / open")
  map_buf(buf, "h", function()
    local r = current()
    if not r then return end
    if r.dir and not state.tree_collapsed[r.path] then
      set_collapsed(r.path, true)
    else
      local parent = r.path:match("(.+)/[^/]+$")
      if parent then goto_path(parent, true) end
    end
  end, "Collapse / parent")
  vim.api.nvim_create_autocmd("CursorMoved", { group = augroup, buffer = buf, callback = function() jump() end })

  rebuild()
  state.tree_refresh = function()
    if not vim.api.nvim_win_is_valid(win) then return end
    local cur = vim.api.nvim_win_get_cursor(win)
    rebuild()
    pcall(vim.api.nvim_win_set_cursor, win, cur)
  end
  -- Keep the tree's cursor on the page's file when the diff flips pages.
  state.tree_goto = function(idx)
    if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_get_current_win() == win then return end
    local r = current()
    if r and r.idx == idx then return end
    for line, row in pairs(rows) do
      if not row.dir and row.idx == idx then
        pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
        return
      end
    end
  end
  -- Park on the current page's file and focus the tree.
  local park
  for line, r in pairs(rows) do
    if not r.dir and r.idx == state.page then park = line break end
  end
  if park then pcall(vim.api.nvim_win_set_cursor, win, { park, 0 }) end
  vim.api.nvim_set_current_win(win)
end

toggle_tree = function()
  state.tree_visible = not state.tree_visible
  if state.mode == "split" then render_split() else render_unified() end
end

-- Re-render at the new editor size, keeping the current file, scroll position
-- and focused pane.
local function rerender_on_resize()
  local diff_win = state.wins.left or state.wins.unified
  if not (diff_win and vim.api.nvim_win_is_valid(diff_win)) then return end
  local cur = vim.api.nvim_get_current_win()
  local focus_key
  for k, w in pairs(state.wins) do
    if w == cur then focus_key = k end
  end
  local view = vim.api.nvim_win_call(diff_win, vim.fn.winsaveview)
  local file_idx
  for i, pos in ipairs(state.file_positions) do
    if pos + 1 <= view.lnum then file_idx = i end
  end

  M.open(state.diff_text, state.title, { focus_file = file_idx })
  refresh_virt_all()

  local function restore()
    for _, key in ipairs({ "unified", "left", "right" }) do
      local w = state.wins[key]
      if w and vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_call, w, function() vim.fn.winrestview(view) end)
      end
    end
    local fw = focus_key and state.wins[focus_key]
    if fw and vim.api.nvim_win_is_valid(fw) and vim.api.nvim_get_current_win() ~= fw then
      vim.api.nvim_set_current_win(fw)
    end
  end
  restore()
  -- The tree's deferred CursorMoved can snap the diff back to the file top.
  vim.defer_fn(restore, 30)
end

local function watch_resize()
  vim.api.nvim_clear_autocmds({ group = resize_group })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    callback = function()
      resize_timer = resize_timer or vim.uv.new_timer()
      resize_timer:stop()
      resize_timer:start(50, 0, vim.schedule_wrap(rerender_on_resize))
    end,
  })
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

--- Open diff viewer.
--- @param diff_text string  Raw diff output
--- @param title string|nil  Window title
--- @param opts table|nil    { pr = { repo = "owner/repo", number = N }, focus_file = idx }
function M.open(diff_text, title, opts)
  opts = opts or {}
  local reapply_blame = state.blame_visible
  if not state.prev_win or not vim.api.nvim_win_is_valid(state.prev_win) then
    state.prev_win = vim.api.nvim_get_current_win()
  end
  state.diff_text = diff_text or ""
  state.title = title or "Diff"
  state.parsed = parse_diff(state.diff_text)
  -- Page to show: the requested file (e.g. from the 'F' picker / Files tab), the
  -- current one on a re-render of the same diff (Tab, resize), else the first.
  if opts.focus_file then
    state.page = opts.focus_file
  elseif state.page_diff ~= state.diff_text then
    state.page = 1
  end
  state.page_diff = state.diff_text
  if opts.pr then
    if not (state.pr and state.pr.repo == opts.pr.repo and state.pr.number == opts.pr.number) then
      state.threads = nil
      state.viewed, state.pr_node_id, state.pr_author = {}, nil, nil
    end
    state.pr = opts.pr
    bind_pending() -- restore this PR's persisted draft review comments
  end
  if state.mode == "split" then
    render_split()
  else
    render_unified()
  end
  if reapply_blame and state.pr then
    state.blame_visible = false
    toggle_blame()
  end
  refresh_virt_all() -- pending 💬 markers + review threads (also after Tab/resize)
  if opts.pr then
    load_threads()
    local pr = state.pr
    gh.pr_viewed_files(pr.repo, pr.number, function(ok, data)
      if not ok or state.pr ~= pr then return end
      state.pr_node_id, state.viewed, state.pr_author = data.id, data.viewed, data.author
      if state.tree_refresh then state.tree_refresh() end
      if state.on_page then state.on_page() end
    end)
  end
  watch_resize()
end

--- Render a unified diff into an existing buffer using the shared diff styling
--- (identical colors/gutters/separators to the float viewer). Used by the
--- side-split git diff so it looks exactly like the devops diff.
--- @param buf integer      target buffer (contents are replaced)
--- @param width integer    window width, for the file/hunk separator rules
--- @param diff_text string raw `git diff` output
--- @return table { files, file_positions, line_map }
function M.render_unified_into(buf, width, diff_text)
  -- Blank diff → clean placeholder (an empty string would otherwise parse into a
  -- phantom "── diff ──" file header).
  if not diff_text or diff_text:match("^%s*$") then
    set_lines(buf, { "", "  No changes" })
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    return { files = {}, file_positions = {}, line_map = {} }
  end
  local files = parse_diff(diff_text)
  local lines, marks, file_positions, line_map = build_unified(files, width)
  set_lines(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  apply_marks(buf, marks)
  return { files = files, file_positions = file_positions, line_map = line_map }
end

--- Parse a raw diff into a path-only file list, for external callers (the
--- changed-files tree). Returns { { path, old_path, new_path }, … } in diff order.
function M.parse_files(diff_text)
  local out = {}
  for _, f in ipairs(parse_diff(diff_text or "")) do
    out[#out + 1] = {
      path = f.new_path or f.old_path or "?",
      old_path = f.old_path,
      new_path = f.new_path,
    }
  end
  return out
end

return M
