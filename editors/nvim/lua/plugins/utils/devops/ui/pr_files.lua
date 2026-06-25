-- PR changed-files browser: a file tree in a left split + the selected file's
-- diff on the right. Open with M.open(pr) where pr has repository.nameWithOwner
-- and number. Self-contained (own tab); the diff pane uses filetype=diff coloring.
local gh = require("plugins.utils.devops.github.api")
local render = require("plugins.utils.devops.ui.render")

local M = {}
local ns = vim.api.nvim_create_namespace("DevOpsPrFiles")
local state = { tab = nil, tree_win = nil, tree_buf = nil, diff_win = nil, diff_buf = nil,
                rows = {}, chunks = {}, order = {}, title = "" }

-- Split a unified diff into { [path] = {lines...} } preserving file order.
local function parse_chunks(diff)
  local chunks, order, cur = {}, {}, nil
  for _, raw in ipairs(vim.split(diff or "", "\n", { plain = true })) do
    local line = raw:gsub("\r$", "")
    local path = line:match("^diff %-%-git a/.- b/(.+)$")
    if path then
      cur = { line }; chunks[path] = cur; order[#order + 1] = path
    elseif cur then
      cur[#cur + 1] = line
    end
  end
  return chunks, order
end

local function counts(chunk)
  local add, del = 0, 0
  for _, l in ipairs(chunk or {}) do
    if l:match("^%+") and not l:match("^%+%+%+") then add = add + 1
    elseif l:match("^%-") and not l:match("^%-%-%-") then del = del + 1 end
  end
  return add, del
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

-- Render the selected file's diff in the right pane.
local function show_diff(path)
  if not (state.diff_buf and vim.api.nvim_buf_is_valid(state.diff_buf)) then return end
  set_lines(state.diff_buf, state.chunks[path] or { "  (no diff)" })
  vim.bo[state.diff_buf].filetype = "diff"
  if state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    pcall(vim.api.nvim_win_set_cursor, state.diff_win, { 1, 0 })
  end
end

-- Render the file tree (grouped by directory) into the tree buffer.
local function render_tree()
  local lines, hls, rows = {}, {}, {}
  local groups, gorder = {}, {}
  for _, path in ipairs(state.order) do
    local dir = path:match("(.+)/[^/]+$") or ""
    if not groups[dir] then groups[dir] = {}; gorder[#gorder + 1] = dir end
    table.insert(groups[dir], path)
  end

  lines[#lines + 1] = "  " .. render.truncate(state.title, 34)
  hls[#hls + 1] = { l = #lines - 1, s = 0, e = #lines[#lines], hl = "DevOpsTitle" }
  lines[#lines + 1] = ""

  for _, dir in ipairs(gorder) do
    if dir ~= "" then
      lines[#lines + 1] = "  ▾ " .. dir
      hls[#hls + 1] = { l = #lines - 1, s = 0, e = #lines[#lines], hl = "DevOpsId" }
    end
    for _, path in ipairs(groups[dir]) do
      local name = path:match("[^/]+$") or path
      local add, del = counts(state.chunks[path])
      local indent = dir ~= "" and "      " or "  "
      local label = indent .. render.truncate(name, 30)
      local stats = "+" .. add .. " -" .. del
      local text = render.pad(label, 40) .. stats
      lines[#lines + 1] = text
      rows[#lines] = path
      local sstart = #render.pad(label, 40)
      hls[#hls + 1] = { l = #lines - 1, s = sstart, e = sstart + #("+" .. add), hl = "DevOpsOk" }
      hls[#hls + 1] = { l = #lines - 1, s = sstart + #("+" .. add) + 1, e = #text, hl = "DevOpsErr" }
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  ↵/j/k browse · q close"
  hls[#hls + 1] = { l = #lines - 1, s = 0, e = #lines[#lines], hl = "DevOpsDim" }

  set_lines(state.tree_buf, lines)
  vim.api.nvim_buf_clear_namespace(state.tree_buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.tree_buf, ns, h.l, h.s, { end_col = h.e, hl_group = h.hl })
  end
  state.rows = rows
end

local function path_under_cursor()
  local line = vim.api.nvim_win_get_cursor(state.tree_win)[1]
  return state.rows[line]
end

local function close()
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    pcall(vim.cmd, "tabclose")
  end
  state.tab, state.tree_win, state.diff_win = nil, nil, nil
end

local function open_layout()
  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()
  state.diff_win = vim.api.nvim_get_current_win()
  state.diff_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.diff_buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(state.diff_win, state.diff_buf)

  vim.cmd("topleft vsplit")
  vim.cmd("vertical resize 44")
  state.tree_win = vim.api.nvim_get_current_win()
  state.tree_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.tree_buf].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(state.tree_win, state.tree_buf)
  vim.wo[state.tree_win].cursorline = true
  vim.wo[state.tree_win].number = false
  vim.wo[state.tree_win].relativenumber = false
  vim.wo[state.tree_win].signcolumn = "no"

  local function tmap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = state.tree_buf, nowait = true })
  end
  local function preview() local p = path_under_cursor(); if p then show_diff(p) end end
  tmap("<CR>", preview)
  tmap("q", close)
  tmap("<Esc>", close)
  -- Live preview as the cursor moves over file rows.
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.tree_buf, callback = preview })
end

-- pr: { repository = { nameWithOwner }, number }
function M.open(pr)
  local repo = pr.repository and pr.repository.nameWithOwner
  local n = pr.number
  if not repo or not n then return vim.notify("DevOps: no PR repo/number", vim.log.levels.WARN) end
  gh.pr_diff(repo, n, function(ok, diff_text, err)
    if not ok then return vim.notify("DevOps: " .. (err or "diff failed"), vim.log.levels.ERROR) end
    state.chunks, state.order = parse_chunks(diff_text)
    if #state.order == 0 then return vim.notify("DevOps: no changed files", vim.log.levels.INFO) end
    state.title = "PR #" .. n .. "  (" .. #state.order .. " files)"
    open_layout()
    render_tree()
    -- Park on the first file row (lowest line number); CursorMoved previews it.
    local first
    for line in pairs(state.rows) do if not first or line < first then first = line end end
    if first then pcall(vim.api.nvim_win_set_cursor, state.tree_win, { first, 0 }) end
    show_diff(state.order[1])
  end)
end

return M
