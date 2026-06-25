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
  line_map = {},   -- [buf_line_1indexed] = { path = "...", line = N }
  pending_comments = {}, -- { { path, line, body }, ... }
  blame_visible = false,
  blame_data = {}, -- [filepath] = { [line_num] = "author date" }
  tree_visible = true, -- file tree pane shown by default; 'f' toggles
  main_win = nil,      -- the diff window the tree jumps/scrolls
}

local render = require("plugins.utils.devops.ui.render")
local TREE_W = 36
local toggle_tree   -- forward-declared; defined after render_unified/render_split
local render_tree_pane -- forward-declared; defined before the render fns

-- Horizontal space the tree pane reserves on the left (0 when hidden).
local function tree_off() return state.tree_visible and (TREE_W + 2) or 0 end

-- Move focus between the diff panes left→right (tree | diff, or tree | old | new).
-- These are floats, so smart-splits/<C-w> can't reach them — we hop explicitly.
local function focus_pane(delta)
  local order, cur = {}, vim.api.nvim_get_current_win()
  for _, key in ipairs({ "tree", "unified", "left", "right" }) do
    local w = state.wins[key]
    if w and vim.api.nvim_win_is_valid(w) then order[#order + 1] = w end
  end
  for i, w in ipairs(order) do
    if w == cur then
      local t = order[i + delta]
      if t then vim.api.nvim_set_current_win(t) end
      return
    end
  end
end

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
  pcall(vim.api.nvim_clear_autocmds, { group = augroup })
end

local function close()
  close_windows()
  state.mode = "split"
  state.pr = nil
  state.pending_comments = {}
  state.blame_visible = false
  state.blame_data = {}
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    vim.api.nvim_set_current_win(state.prev_win)
  end
  state.prev_win = nil
end

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
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
  vim.wo[win].winhighlight = "FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle,CursorLine:Visual"
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

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local function jump_file(delta)
  local pos = state.file_positions
  if #pos == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  local target
  if delta > 0 then
    for _, p in ipairs(pos) do
      if p > cur then target = p; break end
    end
    target = target or pos[1]
  else
    for i = #pos, 1, -1 do
      if pos[i] < cur then target = pos[i]; break end
    end
    target = target or pos[#pos]
  end
  vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
end

---------------------------------------------------------------------------
-- Inline comments & review submission
---------------------------------------------------------------------------

local input = require("plugins.utils.devops.ui.input")
local gh = require("plugins.utils.devops.github.api")

local function get_line_info()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_map[line]
end

local function show_pending_virt(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns_comments, 0, -1)
  for _, c in ipairs(state.pending_comments) do
    for lnum, info in pairs(state.line_map) do
      if info.path == c.path and info.line == c.line then
        local preview = require("plugins.utils.devops.ui.render").truncate((c.body or ""):gsub("\n", " "), 60)
        pcall(vim.api.nvim_buf_set_extmark, buf, ns_comments, lnum - 1, 0, {
          virt_text = { { "  💬 " .. preview, "DevOpsWarn" } },
          virt_text_pos = "eol",
        })
        break
      end
    end
  end
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
  input.open("Comment on " .. info.path .. ":" .. info.line, nil, function(body)
    if not body or body:match("^%s*$") then return end
    state.pending_comments[#state.pending_comments + 1] = {
      path = info.path,
      line = info.line,
      body = body,
    }
    vim.notify(string.format("DevOps: comment queued (%d pending)", #state.pending_comments), vim.log.levels.INFO)
    -- Show virtual text on all active diff buffers
    for _, key in ipairs({ "unified", "left", "right" }) do
      local b = state.bufs[key]
      if b and vim.api.nvim_buf_is_valid(b) then show_pending_virt(b) end
    end
  end)
end

local function submit_review()
  if not state.pr then
    vim.notify("DevOps: no PR context — open diff from a PR", vim.log.levels.WARN)
    return
  end
  local items = {
    "Comment — Submit general feedback",
    "Approve — Approve merging these changes",
    "Request changes — Suggest changes before merging",
  }
  vim.ui.select(items, { prompt = "Submit review:" }, function(choice)
    if not choice then return end
    local event = choice:match("^Approve") and "APPROVE"
      or choice:match("^Request") and "REQUEST_CHANGES"
      or "COMMENT"
    local pending = state.pending_comments
    local function do_submit(body)
      gh.pr_review(state.pr.repo, state.pr.number, event, body, pending, function(ok, _, err)
        if not ok then
          return vim.notify("DevOps: review failed — " .. (err or "unknown"), vim.log.levels.ERROR)
        end
        state.pending_comments = {}
        local label = event == "APPROVE" and "approved"
          or event == "REQUEST_CHANGES" and "changes requested"
          or "commented"
        local count = #pending > 0 and string.format(" (%d inline comments)", #pending) or ""
        vim.notify("DevOps: review submitted — " .. label .. count, vim.log.levels.INFO)
      end)
    end
    if event == "APPROVE" and #pending == 0 then
      do_submit("")
    else
      input.open("Review body (" .. event:lower():gsub("_", " ") .. ")", nil, function(body)
        do_submit(body or "")
      end)
    end
  end)
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
  map_buf(buf, "<Esc>", close, "Close diff") -- <C-d> is left free for half-page scroll
  map_buf(buf, "<Tab>", function()
    state.mode = state.mode == "unified" and "split" or "unified"
    M.open(state.diff_text, state.title)
  end, "Toggle diff mode")
  map_buf(buf, "T", function()
    local render = require("plugins.utils.devops.ui.render")
    local name = render.cycle_diff_theme(1)
    vim.notify("Diff theme: " .. name, vim.log.levels.INFO, { title = "DevOps" })
    M.open(state.diff_text, state.title)
  end, "Cycle diff theme")
  map_buf(buf, "B", toggle_blame, "Toggle blame")
  map_buf(buf, "f", function() toggle_tree() end, "Toggle file tree")
  map_buf(buf, "<S-Left>", function() focus_pane(-1) end, "Focus pane left")
  map_buf(buf, "<S-Right>", function() focus_pane(1) end, "Focus pane right")
  map_buf(buf, "]f", function() jump_file(1) end, "Next file")
  map_buf(buf, "[f", function() jump_file(-1) end, "Prev file")
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
    map_buf(buf, "S", submit_review, "Submit review")
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
      { "S ", "DevOpsKey" }, { "submit review" .. badge, "DevOpsAction" },
    })
  end
  vim.list_extend(parts, {
    { sep, nil },
    { "T ", "DevOpsKey" }, { "theme", "DevOpsAction" },
    { "  ", nil },
    { "B ", "DevOpsKey" }, { "blame", "DevOpsAction" },
    { "  ", nil },
    { "f ", "DevOpsKey" }, { "tree", "DevOpsAction" },
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
-- File tree pane (left) — lists the parsed files; cursor/↵ jumps the diff.
---------------------------------------------------------------------------

-- Render the left file-tree float. `main_win` is the diff window it drives.
render_tree_pane = function(total_h)
  if not state.tree_visible then return end
  local files = state.parsed or {}
  local lines, hls, rows = {}, {}, {}
  local groups, gorder = {}, {}
  for i, f in ipairs(files) do
    local path = f.new_path or f.old_path or "?"
    local dir = path:match("(.+)/[^/]+$") or ""
    if not groups[dir] then groups[dir] = {}; gorder[#gorder + 1] = dir end
    table.insert(groups[dir], { idx = i, path = path })
  end
  lines[#lines + 1] = "  Changed files (" .. #files .. ")"
  hls[#hls + 1] = { l = 0, s = 0, e = #lines[1], g = "DevOpsTitle" }
  lines[#lines + 1] = ""
  for _, dir in ipairs(gorder) do
    if dir ~= "" then
      lines[#lines + 1] = "  ▾ " .. render.truncate(dir, TREE_W - 4)
      hls[#hls + 1] = { l = #lines - 1, s = 0, e = #lines[#lines], g = "DevOpsId" }
    end
    for _, ent in ipairs(groups[dir]) do
      local name = ent.path:match("[^/]+$") or ent.path
      local indent = dir ~= "" and "      " or "  "
      lines[#lines + 1] = indent .. render.truncate(name, TREE_W - #indent - 1)
      rows[#lines] = ent.idx
    end
  end

  local buf = make_buf()
  state.bufs.tree = buf
  set_lines(buf, lines)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.l, h.s, { end_col = h.e, hl_group = h.g })
  end
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", width = TREE_W, height = total_h, row = 0, col = 0,
    style = "minimal", border = "rounded", title = " files ", title_pos = "center",
  })
  state.wins.tree = win
  set_win_opts(win)
  vim.wo[win].cursorline = true

  local function jump()
    local idx = rows[vim.api.nvim_win_get_cursor(win)[1]]
    if not idx then return end
    local pos = state.file_positions[idx]
    if not pos then return end
    -- Move every diff pane (programmatic cursor sets don't trigger scrollbind).
    for _, key in ipairs({ "unified", "left", "right" }) do
      local w = state.wins[key]
      if w and vim.api.nvim_win_is_valid(w) then
        pcall(vim.api.nvim_win_set_cursor, w, { pos + 1, 0 })
        pcall(vim.api.nvim_win_call, w, function() vim.cmd("normal! zt") end)
      end
    end
  end
  setup_keymaps(buf) -- q/f/T/B/]f… also work from the tree
  vim.keymap.set("n", "<CR>", function()
    jump()
    if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
      vim.api.nvim_set_current_win(state.main_win)
    end
  end, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd("CursorMoved", { group = augroup, buffer = buf, callback = jump })
  -- Park on the first file row (lowest line) and focus the tree.
  local first
  for line in pairs(rows) do if not first or line < first then first = line end end
  if first then pcall(vim.api.nvim_win_set_cursor, win, { first, 0 }) end
  vim.api.nvim_set_current_win(win)
end

---------------------------------------------------------------------------
-- Unified
---------------------------------------------------------------------------

local function render_unified()
  close_windows()
  local files = state.parsed or {}
  local lines, marks = {}, {}
  state.file_positions = {}

  local off = tree_off()
  local total_w = vim.o.columns - 2 - off
  local total_h = vim.o.lines - 4

  local line_map = {}

  for fi, file in ipairs(files) do
    if fi > 1 then
      local rule = sep_rule(total_w)
      lines[#lines + 1] = rule
      marks[#marks + 1] = { line = #lines - 1, type = "sep" }
      lines[#lines + 1] = rule
      marks[#marks + 1] = { line = #lines - 1, type = "sep" }
    end
    local title = file.new_path or file.old_path or "unknown"
    local fpath = file.new_path or file.old_path or ""

    state.file_positions[#state.file_positions + 1] = #lines
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
          line_map[#lines] = { path = fpath, line = new_ln }
          new_ln = new_ln + 1
        elseif prefix == "-" then
          lines[#lines + 1] = gutter(old_ln) .. content
          marks[#marks + 1] = { line = #lines - 1, type = "del", gutter_end = g }
          line_map[#lines] = { path = fpath, line = old_ln }
          old_ln = old_ln + 1
        elseif prefix == " " then
          lines[#lines + 1] = gutter(new_ln) .. content
          marks[#marks + 1] = { line = #lines - 1, type = "ctx", gutter_end = g }
          line_map[#lines] = { path = fpath, line = new_ln }
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
  state.main_win = win
  set_win_opts(win)
  setup_keymaps(buf)
  render_footer(total_w, total_h + 2)
  render_tree_pane(total_h)
end

---------------------------------------------------------------------------
-- Split
---------------------------------------------------------------------------

local function build_split_data(files, pane_width)
  local left, right = {}, {}
  local left_marks, right_marks = {}, {}
  local file_pos = {}
  local line_map = {}

  local function add(fpath, lhs, rhs, ltype, rtype, map_line)
    left[#left + 1] = lhs or ""
    right[#right + 1] = rhs or ""
    if ltype then left_marks[#left_marks + 1] = { line = #left - 1, type = ltype } end
    if rtype then right_marks[#right_marks + 1] = { line = #right - 1, type = rtype } end
    if map_line and fpath then
      line_map[#right] = { path = fpath, line = map_line }
    end
  end

  for fi, file in ipairs(files) do
    if fi > 1 then
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
            r_ln or l_ln
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
          add(fpath, gutter(old_ln) .. content, gutter(new_ln) .. content, "ctx", "ctx", new_ln)
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

  return left, right, left_marks, right_marks, file_pos, line_map
end

local function render_split()
  close_windows()
  local files = state.parsed or {}
  local off = tree_off()
  local total_w = vim.o.columns - 4 - off
  local left_w = math.floor(total_w / 2)
  local left_lines, right_lines, left_marks, right_marks, file_pos, line_map = build_split_data(files, left_w)
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
  state.main_win = left_win
  set_win_opts(left_win)
  set_win_opts(right_win)

  for _, win in ipairs({ left_win, right_win }) do
    vim.wo[win].scrollbind = true
    vim.wo[win].cursorbind = true
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    setup_keymaps(buf)
  end

  -- Dynamic title showing current file
  local function update_titles()
    local line = 1
    if left_win and vim.api.nvim_win_is_valid(left_win) then
      line = vim.api.nvim_win_get_cursor(left_win)[1]
    end
    local current_file = ""
    for _, fp in ipairs(file_pos) do
      if fp + 1 <= line then
        current_file = (left_lines[fp + 1] or ""):match("^%s*(.-)%s*$") or ""
      end
    end
    local suffix = current_file ~= "" and (" · " .. current_file) or ""
    pcall(function()
      local cfg = vim.api.nvim_win_get_config(left_win)
      cfg.title = " " .. base .. suffix .. " · old "
      cfg.title_pos = "center"
      vim.api.nvim_win_set_config(left_win, cfg)
    end)
    pcall(function()
      local cfg = vim.api.nvim_win_get_config(right_win)
      cfg.title = " " .. base .. suffix .. " · new "
      cfg.title_pos = "center"
      vim.api.nvim_win_set_config(right_win, cfg)
    end)
  end

  for _, buf in ipairs({ left_buf, right_buf }) do
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = augroup, buffer = buf, callback = update_titles,
    })
  end
  update_titles()
  render_footer(vim.o.columns - 2, total_h + 2)
  render_tree_pane(total_h)
end

-- Toggle the file tree pane and re-render the current mode.
toggle_tree = function()
  state.tree_visible = not state.tree_visible
  if state.mode == "split" then render_split() else render_unified() end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

--- Open diff viewer.
--- @param diff_text string  Raw diff output
--- @param title string|nil  Window title
--- @param opts table|nil    { pr = { repo = "owner/repo", number = N } }
function M.open(diff_text, title, opts)
  opts = opts or {}
  local reapply_blame = state.blame_visible
  if not state.prev_win or not vim.api.nvim_win_is_valid(state.prev_win) then
    state.prev_win = vim.api.nvim_get_current_win()
  end
  state.diff_text = diff_text or ""
  state.title = title or "Diff"
  state.parsed = parse_diff(state.diff_text)
  if opts.pr then
    state.pr = opts.pr
    state.pending_comments = {}
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
end

return M
