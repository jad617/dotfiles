---------------------------------------------------------------------------
-- Detail view — a large centered float showing a Jira issue or a GitHub PR
-- as an atlas-style card: header, metadata block, badges, linked items, body.
---------------------------------------------------------------------------

local client = require("plugins.utils.devops.jira.client")
local api = require("plugins.utils.devops.jira.api")
local adf = require("plugins.utils.devops.jira.adf")
local gh = require("plugins.utils.devops.github.api")
local input = require("plugins.utils.devops.ui.input")
local diff_viewer = require("plugins.utils.devops.ui.diff_viewer")
local render = require("plugins.utils.devops.ui.render")
local user_picker = require("plugins.utils.devops.ui.user_picker")

local M = {}

local ns = vim.api.nvim_create_namespace("DevOpsDetail")
local state = { win = nil, buf = nil, prev_win = nil, comment_rows = {} }

---------------------------------------------------------------------------
-- Render builder output into an external buffer (for inline/nav-stack use).
-- Returns the highlight data for the caller to apply.
---------------------------------------------------------------------------
function M.write_to_buf(buf, b)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, b.lines())
  vim.bo[buf].modifiable = false
  local ns_ext = vim.api.nvim_create_namespace("DevOps")
  vim.api.nvim_buf_clear_namespace(buf, ns_ext, 0, -1)
  for _, h in ipairs(b.highlights()) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_ext, h.line, h.col_start, {
      end_col = h.col_end, hl_group = h.hl,
    })
  end
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  -- Restore focus to the window that opened the detail (dashboard content).
  if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
    vim.api.nvim_set_current_win(state.prev_win)
  end
  state.win, state.buf, state.prev_win = nil, nil, nil
end

-- A tiny builder so callers can emit (line, highlight) pairs declaratively.
local function builder()
  local L, H = {}, {}
  local b = {}
  function b.add(text)
    L[#L + 1] = text or ""
    return #L -- 1-based line number
  end
  function b.hl(line1, col_start, col_end, group)
    H[#H + 1] = { line = line1 - 1, col_start = col_start, col_end = col_end, hl = group }
  end
  -- "label   value" row with a dim label and an optionally-colored value.
  function b.field(label, value, vhl)
    if value == nil or value == "" then return end
    local prefix = "  " .. render.pad(label, 11) .. " "
    local line = b.add(prefix .. value)
    b.hl(line, 0, #prefix, "DevOpsDim")
    if vhl then b.hl(line, #prefix, #prefix + #tostring(value), vhl) end
    return line
  end
  function b.divider(title)
    b.add("")
    b.add("  " .. string.rep("─", 64))
    if title then
      local t = "  " .. title
      local line = b.add(t)
      b.hl(line, 0, #t, "DevOpsSectionHead")
    end
  end
  function b.lines() return L end
  function b.highlights() return H end
  return b
end

-- Open / refresh the float with the given builder output. on_open(buf) hooks keys.
local function show(title, b, on_open)
  local lines = b.lines()
  -- Cover ~75% of the editor, centered (consistent large popup).
  local width = math.max(60, math.floor(vim.o.columns * 0.75))
  local height = math.max(15, math.floor(vim.o.lines * 0.75))

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "wipe"
  end
  local buf = state.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(b.highlights()) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.line, h.col_start, {
      end_col = h.col_end, hl_group = h.hl,
    })
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      relative = "editor", width = width, height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
    })
  else
    -- Remember the caller's window so we can restore focus on close.
    state.prev_win = vim.api.nvim_get_current_win()
    state.win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", width = width, height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal", border = "rounded",
      title = " " .. title .. " ", title_pos = "center",
    })
    vim.wo[state.win].wrap = true
    vim.wo[state.win].cursorline = true
    vim.wo[state.win].winhighlight = "FloatBorder:DevOpsBorder,FloatTitle:DevOpsTitle"
    for _, k in ipairs({ "q", "<C-d>", "<Esc>" }) do
      vim.keymap.set("n", k, close, { buffer = buf, nowait = true, desc = "Close" })
    end
  end
  if on_open then on_open(buf) end
end

-- Mention handler for Jira input floats: opens the live-search user picker
-- and inserts @[Name]{id} at cursor.
local function jira_mention()
  return function(insert_fn)
    user_picker.open(function(choice)
      insert_fn("@[" .. choice.name .. "]{" .. choice.id .. "}")
    end, { title = "Mention User" })
  end
end

---------------------------------------------------------------------------
-- Jira issue
---------------------------------------------------------------------------
local function field_path(issue, path, default)
  local node = issue.fields or {}
  for part in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return default end
    node = node[part]
  end
  if node == nil then return default end
  return node
end

-- Format an ISO 8601 date string to a short relative/absolute label.
local function format_time(iso)
  if not iso or iso == "" then return "" end
  -- parse "2026-06-11T18:12:41Z" or "2026-06-11T18:12:41+00:00"
  local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return iso:sub(1, 10) end
  local ts = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) })
  local diff = os.time() - ts
  if diff < 60 then return "just now"
  elseif diff < 3600 then return math.floor(diff / 60) .. "m ago"
  elseif diff < 86400 then return math.floor(diff / 3600) .. "h ago"
  elseif diff < 604800 then return math.floor(diff / 86400) .. "d ago"
  else return ("%04d-%02d-%02d"):format(tonumber(y), tonumber(mo), tonumber(d)) end
end

local function active_sprint_name(f)
  local cf = f.customfield_10020
  if type(cf) ~= "table" then return nil end
  local name
  for _, s in ipairs(cf) do
    if type(s) == "table" and s.name then
      name = s.name
      if s.state == "active" then return s.name end
    end
  end
  return name
end

local function build_issue(issue, prs, comments)
  local f = issue.fields or {}
  local b = builder()

  -- Header: type icon + key, then the summary as the card title.
  local icon = render.issue_icon(f.issuetype and f.issuetype.name)
  local key = issue.key or "?"
  local hl = b.add("  " .. icon .. "  " .. key)
  b.hl(hl, 2, 2 + #icon, "DevOpsIcon")
  b.hl(hl, #("  " .. icon .. "  "), #("  " .. icon .. "  ") + #key, "DevOpsId")
  local tl = b.add("  " .. (f.summary or ""))
  b.hl(tl, 0, #b.lines()[tl], "DevOpsDetailTitle")
  b.add("")

  -- Metadata block.
  local cat = f.status and f.status.statusCategory and f.status.statusCategory.key
  b.field("Status", field_path(issue, "status.name", "?"), render.status_hl(cat))
  b.field("Type", field_path(issue, "issuetype.name", nil))
  b.field("Assignee", field_path(issue, "assignee.displayName", "Unassigned"))
  b.field("Reporter", field_path(issue, "reporter.displayName", nil))
  b.field("Priority", field_path(issue, "priority.name", nil))
  b.field("Sprint", active_sprint_name(f), "DevOpsWarn")
  if f.parent then
    b.field("Parent", (f.parent.key or "") .. "  " .. field_path(issue, "parent.fields.summary", ""))
  end
  if type(f.labels) == "table" and #f.labels > 0 then
    b.field("Labels", table.concat(f.labels, "  "), "DevOpsLabel")
  end
  b.field("Updated", (f.updated or ""):sub(1, 10))

  -- Linked PRs.
  b.divider("Linked PRs")
  if prs == nil then
    local l = b.add("   loading…")
    b.hl(l, 0, #b.lines()[l], "DevOpsDim")
  elseif #prs == 0 then
    local l = b.add("   none")
    b.hl(l, 0, #b.lines()[l], "DevOpsDim")
  else
    for _, pr in ipairs(prs) do
      local stt = pr.status or pr.state or ""
      local ok = stt == "MERGED" or stt == "OPEN"
      local l = b.add(("   %s  %s  [%s]"):format(pr.id or "", pr.name or pr.title or "", stt))
      b.hl(l, 3, 3 + #(pr.id or ""), "DevOpsId")
      b.hl(l, #b.lines()[l] - #stt - 1, #b.lines()[l], ok and "DevOpsOk" or "DevOpsWarn")
      if pr.url then
        local u = b.add("       " .. pr.url)
        b.hl(u, 0, #b.lines()[u], "DevOpsDim")
      end
    end
  end

  -- Description.
  b.divider("Description")
  for _, line in ipairs(adf.adf_to_lines(f.description)) do b.add("  " .. (line:gsub("\r", ""))) end

  -- Comments.
  local comment_rows = {} -- 1-based line → comment object

  -- Detect if a comment is a reply: its ADF body starts with a mention of
  -- someone who authored a previous comment in this thread.
  local function is_reply(comment, prev_author_ids)
    local body = comment.body
    if type(body) ~= "table" or not body.content then return false end
    local first_block = body.content[1]
    if not first_block or not first_block.content then return false end
    local first_inline = first_block.content[1]
    if not first_inline or first_inline.type ~= "mention" then return false end
    local mentioned_id = first_inline.attrs and first_inline.attrs.id
    return mentioned_id and prev_author_ids[mentioned_id] or false
  end

  -- Card-style comment rendering.
  -- Cards fill the available float width minus indent and a small right margin.
  local float_w = math.max(60, math.floor(vim.o.columns * 0.75))

  -- Word-wrap a string to fit within max_w characters.
  local function wrap(str, max_w)
    if #str <= max_w then return { str } end
    local result = {}
    local pos = 1
    while pos <= #str do
      if #str - pos + 1 <= max_w then
        result[#result + 1] = str:sub(pos)
        break
      end
      local chunk = str:sub(pos, pos + max_w - 1)
      local break_at = chunk:match(".*()%s")
      if break_at and break_at > 1 then
        result[#result + 1] = str:sub(pos, pos + break_at - 2)
        pos = pos + break_at
      else
        result[#result + 1] = chunk
        pos = pos + max_w
      end
    end
    return result
  end

  --- Render a comment as a bordered card.
  --- @param comment table  Jira comment object
  --- @param indent number  left padding in spaces
  --- @param border_hl string  highlight group for border chars (╭│╰─╮╯)
  local function render_card(comment, indent, border_hl)
    local pad = string.rep(" ", indent)
    local card_w = float_w - indent - 2
    if card_w < 30 then card_w = 30 end
    local inner_w = card_w - 2
    local author = comment.author and comment.author.displayName or "?"
    local date = (comment.created or ""):sub(1, 10)

    -- ╭─ Author ─────────────────────────── 2026-06-10 ─╮
    local top_left = "╭─ "
    local top_right = " ─╮"
    local date_part = " " .. date .. " "
    local fill_len = card_w - #top_left - #author - #date_part - #top_right + 4
    if fill_len < 2 then fill_len = 2 end
    local top_border = top_left .. author .. " " .. string.rep("─", fill_len) .. date_part .. top_right
    local top_line = b.add(pad .. top_border)
    comment_rows[top_line] = comment
    local a_start = #pad + #top_left
    b.hl(top_line, 0, a_start, border_hl)
    b.hl(top_line, a_start, a_start + #author, "DevOpsId")
    local after_author = a_start + #author
    local date_start = #pad + #top_border - #top_right - #date_part
    b.hl(top_line, after_author, date_start, border_hl)
    b.hl(top_line, date_start, date_start + #date_part, "DevOpsDim")
    b.hl(top_line, date_start + #date_part, #pad + #top_border, border_hl)

    -- │ (breathing room)
    local empty_inner = "│" .. string.rep(" ", inner_w) .. "│"
    local el = b.add(pad .. empty_inner)
    comment_rows[el] = comment
    b.hl(el, 0, #pad + 1, border_hl)
    b.hl(el, #pad + #empty_inner - 1, #pad + #empty_inner, border_hl)

    -- │  body text lines  │  (word-wrapped)
    local text_w = inner_w - 2
    for _, bline in ipairs(adf.adf_to_lines(comment.body)) do
      local clean = bline:gsub("\r", "")
      if clean == "" then clean = " " end
      for _, wline in ipairs(wrap(clean, text_w)) do
        local text = "  " .. wline
        local body_row = "│" .. text .. string.rep(" ", inner_w - #text) .. "│"
        local cl = b.add(pad .. body_row)
        comment_rows[cl] = comment
        b.hl(cl, 0, #pad + 1, border_hl)
        b.hl(cl, #pad + #body_row - 1, #pad + #body_row, border_hl)
      end
    end

    -- │ (breathing room)
    local el2 = b.add(pad .. empty_inner)
    comment_rows[el2] = comment
    b.hl(el2, 0, #pad + 1, border_hl)
    b.hl(el2, #pad + #empty_inner - 1, #pad + #empty_inner, border_hl)

    -- ╰──────────────────────────────────────────────────╯
    local bottom = "╰" .. string.rep("─", inner_w) .. "╯"
    local bl = b.add(pad .. bottom)
    comment_rows[bl] = comment
    b.hl(bl, 0, #pad + #bottom, border_hl)
  end

  b.divider("Comments")
  if comments == nil then
    local l = b.add("   loading…")
    b.hl(l, 0, #b.lines()[l], "DevOpsDim")
  elseif #comments == 0 then
    local l = b.add("   no comments")
    b.hl(l, 0, #b.lines()[l], "DevOpsDim")
  else
    local seen_authors = {} -- accountId → true for all previous comment authors
    for i, comment in ipairs(comments) do
      local reply = is_reply(comment, seen_authors)
      if reply then
        b.add("")
        local arrow = "      ╰──▶ reply"
        local al = b.add(arrow)
        b.hl(al, 0, 11, "DevOpsReplyBorder")
        b.hl(al, 11, #arrow, "DevOpsReplyLabel")
        render_card(comment, 6, "DevOpsReplyBorder")
      else
        render_card(comment, 2, "DevOpsCommentBorder")
      end
      -- Track this comment's author for future reply detection
      local aid = comment.author and comment.author.accountId
      if aid then seen_authors[aid] = true end
      if i < #comments then b.add("") end
    end
  end

  return b, comment_rows
end

function M.open_issue(key)
  api.get_issue(key, function(ok, issue, err)
    if not ok or not issue then
      return vim.notify("DevOps: " .. (err or ("failed to load " .. key)), vim.log.levels.ERROR)
    end
    local browse = client.base_url() .. "/browse/" .. issue.key
    local project_key = key:match("^(%u+)-")

    local function setup_keys(buf)
      vim.keymap.set("n", "o", function() vim.ui.open(browse) end, { buffer = buf, desc = "Open in browser" })

      -- Comment
      vim.keymap.set("n", "c", function()
        input.open("Comment " .. key, "", function(text)
          if text == "" then return end
          api.add_comment(key, text, function(ok3, _, err3)
            if not ok3 then return vim.notify("DevOps: " .. (err3 or "comment failed"), vim.log.levels.ERROR) end
            vim.notify("DevOps: comment added to " .. key, vim.log.levels.INFO)
            M.open_issue(key)
          end)
        end, { on_mention = jira_mention() })
      end, { buffer = buf, desc = "Comment" })

      -- Reply to comment under cursor (or pick if cursor not on a comment)
      vim.keymap.set("n", "r", function()
        local cursor = vim.api.nvim_win_get_cursor(state.win)
        local cmt = state.comment_rows[cursor[1]]
        if cmt then
          -- Cursor is on a comment — reply directly
          local author = cmt.author and cmt.author.displayName or "?"
          local author_id = cmt.author and cmt.author.accountId
          local body_lines = adf.adf_to_lines(cmt.body)
          -- Show the original comment as read-only context in the title,
          -- but only submit the user's new text (with the mention tag).
          local prefill = ""
          if author_id then
            prefill = "@[" .. author .. "]{" .. author_id .. "} "
          end
          input.open("Reply " .. key, prefill, function(text)
            -- Strip the mention tag to check if user actually typed something
            local stripped = text:gsub("@%[.-%]%{.-%}", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if stripped == "" then return end
            api.add_comment(key, text, function(ok3, _, err3)
              if not ok3 then return vim.notify("DevOps: " .. (err3 or "reply failed"), vim.log.levels.ERROR) end
              vim.notify("DevOps: reply added to " .. key, vim.log.levels.INFO)
              M.open_issue(key)
            end)
          end, { on_mention = jira_mention() })
        else
          vim.notify("DevOps: move cursor to a comment to reply", vim.log.levels.INFO)
        end
      end, { buffer = buf, desc = "Reply to comment" })

      -- Edit
      vim.keymap.set("n", "e", function()
        api.get_issue(key, function(ok3, iss, err3)
          if not ok3 then return vim.notify("DevOps: " .. (err3 or "fetch failed"), vim.log.levels.ERROR) end
          local f = iss.fields or {}
          vim.ui.input({ prompt = "Summary: ", default = f.summary or "" }, function(new_summary)
            if not new_summary then return end
            local desc_text = table.concat(adf.adf_to_lines(f.description), "\n")
            input.open("Description " .. key, desc_text, function(new_desc)
              local fields = {}
              if new_summary ~= (f.summary or "") then fields.summary = new_summary end
              fields.description = adf.text_to_adf(new_desc)
              api.update_issue(key, fields, function(ok4, _, err4)
                if not ok4 then return vim.notify("DevOps: " .. (err4 or "update failed"), vim.log.levels.ERROR) end
                vim.notify("DevOps: " .. key .. " updated", vim.log.levels.INFO)
                -- Refresh detail
                M.open_issue(key)
              end)
            end)
          end)
        end)
      end, { buffer = buf, desc = "Edit" })

      -- Assign
      vim.keymap.set("n", "a", function()
        api.assignable_users(project_key, function(ok3, users, err3)
          if not ok3 then return vim.notify("DevOps: " .. (err3 or "user lookup failed"), vim.log.levels.ERROR) end
          local choices = {}
          local me_id = client.account_id()
          if me_id then
            choices[#choices + 1] = { label = "● Me (" .. (client.display_name() or "") .. ")", account_id = me_id }
          end
          choices[#choices + 1] = { label = "✗ Unassigned", account_id = nil }
          for _, u in ipairs(users) do
            if u.accountId and u.accountType ~= "app" then
              choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
            end
          end
          vim.ui.select(choices, {
            prompt = "Assign " .. key .. " to:",
            format_item = function(c) return c.label end,
          }, function(choice)
            if not choice then return end
            api.assign(key, choice.account_id, function(ok4, _, err4)
              if not ok4 then return vim.notify("DevOps: " .. (err4 or "assign failed"), vim.log.levels.ERROR) end
              vim.notify("DevOps: " .. key .. " assigned to " .. choice.label, vim.log.levels.INFO)
              M.open_issue(key)
            end)
          end)
        end)
      end, { buffer = buf, desc = "Assign" })
    end

    local b_initial, cr_initial = build_issue(issue, nil, nil)
    state.comment_rows = cr_initial
    show("Jira · " .. issue.key, b_initial, function(buf)
      setup_keys(buf)
      -- Linked PRs and comments arrive async; rebuild as each completes.
      local async_prs, async_comments
      local function rebuild()
        if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
        local b_new, cr_new = build_issue(issue, async_prs, async_comments)
        state.comment_rows = cr_new
        show("Jira · " .. issue.key, b_new, setup_keys)
      end
      api.dev_status(issue.id, function(ok2, prs)
        async_prs = ok2 and prs or {}
        rebuild()
      end)
      api.comments(issue.key, function(ok2, cmts)
        async_comments = ok2 and cmts or {}
        rebuild()
      end)
    end)
  end)
end

---------------------------------------------------------------------------
-- GitHub PR
---------------------------------------------------------------------------
local function checks_summary(rollup)
  if type(rollup) ~= "table" or #rollup == 0 then return nil end
  local pass, fail, pend = 0, 0, 0
  for _, c in ipairs(rollup) do
    local s = c.conclusion or c.state or ""
    if s == "SUCCESS" or s == "NEUTRAL" or s == "SKIPPED" then
      pass = pass + 1
    elseif s == "FAILURE" or s == "ERROR" or s == "TIMED_OUT" or s == "CANCELLED" or s == "ACTION_REQUIRED" then
      fail = fail + 1
    else
      pend = pend + 1
    end
  end
  return pass, fail, pend
end

local REVIEW_LABEL = {
  APPROVED = "approved", CHANGES_REQUESTED = "changes requested", REVIEW_REQUIRED = "review required",
}

local function gh_person_name(person)
  if type(person) ~= "table" then return nil end
  return person.displayName or person.name or person.login or person.slug
end

local function gh_person_key(person)
  if type(person) ~= "table" then return nil end
  return person.login or person.slug or person.name or person.displayName
end

local function review_request_name(req)
  if type(req) ~= "table" then return nil end
  local reviewer = req.requestedReviewer or req.reviewer or req.user or req.team or req
  return gh_person_name(reviewer), gh_person_key(reviewer)
end

local function review_rows(pr)
  local rows, by_key = {}, {}
  local function upsert(key, name, verdict, hl, order)
    if not key or key == "" or not name or name == "" then return end
    local existing = by_key[key]
    if existing and existing.order > order then return end
    if existing then
      existing.verdict = verdict
      existing.hl = hl
      existing.order = order
    else
      local row = { key = key, name = name, verdict = verdict, hl = hl, order = order }
      by_key[key] = row
      rows[#rows + 1] = row
    end
  end

  local author_key = gh_person_key(pr.author)
  for i, review in ipairs(pr.reviews or {}) do
    local author = gh_person_name(review.author)
    local key = gh_person_key(review.author)
    if author and key and key ~= author_key then
      local state = review.state or ""
      if state == "APPROVED" then
        upsert(key, author, "approved", "DevOpsOk", i)
      elseif state == "CHANGES_REQUESTED" then
        upsert(key, author, "changes_requested", "DevOpsErr", i)
      elseif state ~= "" and state ~= "DISMISSED" then
        upsert(key, author, "pending", "DevOpsWarn", i)
      end
    end
  end

  for _, request in ipairs(pr.reviewRequests or {}) do
    local name, key = review_request_name(request)
    if key and not by_key[key] then
      upsert(key, name, "pending", "DevOpsWarn", 0)
    end
  end

  table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
  return rows
end

local function count_items(items)
  return type(items) == "table" and #items or 0
end

local function mergeable_text(pr)
  local parts = {}
  if pr.mergeStateStatus and pr.mergeStateStatus ~= "" then
    parts[#parts + 1] = pr.mergeStateStatus:lower():gsub("_", " ")
  end
  if pr.mergeable and pr.mergeable ~= "" then
    parts[#parts + 1] = pr.mergeable:lower():gsub("_", " ")
  end
  return #parts > 0 and table.concat(parts, " · ") or nil
end

local function build_pr(pr)
  local b = builder()
  local draft = pr.isDraft
  local icon = draft and "" or ""

  local hl = b.add("  " .. icon .. "  #" .. tostring(pr.number or "?"))
  b.hl(hl, 2, 2 + #icon, draft and "DevOpsPrDraft" or "DevOpsPrOpen")
  b.hl(hl, #("  " .. icon .. "  "), #b.lines()[hl], "DevOpsId")
  local tl = b.add("  " .. (pr.title or ""))
  b.hl(tl, 0, #b.lines()[tl], "DevOpsDetailTitle")
  b.add("")

  local stateStr = draft and "DRAFT" or (pr.state or "?")
  b.field("State", stateStr, draft and "DevOpsPrDraft" or "DevOpsPrOpen")
  if pr.reviewDecision and pr.reviewDecision ~= "" then
    local rd = REVIEW_LABEL[pr.reviewDecision] or pr.reviewDecision
    b.field("Review", rd, pr.reviewDecision == "APPROVED" and "DevOpsOk"
      or (pr.reviewDecision == "CHANGES_REQUESTED" and "DevOpsErr" or "DevOpsWarn"))
  end
  b.field("Author", pr.author and pr.author.login or nil)
  if pr.repository and pr.repository.nameWithOwner then
    b.field("Repo", pr.repository.nameWithOwner, "DevOpsId")
  end
  local assignees = nil
  if pr.assignees ~= nil then
    assignees = {}
    for _, assignee in ipairs(pr.assignees or {}) do
      assignees[#assignees + 1] = gh_person_name(assignee)
    end
    b.field("Assignees", #assignees > 0 and table.concat(assignees, ", ") or "None")
  end
  if pr.headRefName then
    b.field("Branch", pr.headRefName .. "  →  " .. (pr.baseRefName or "?"))
  end
  if pr.additions or pr.deletions then
    b.field("Diff", ("+%d  -%d"):format(pr.additions or 0, pr.deletions or 0), "DevOpsWarn")
  end
  if pr.files ~= nil then b.field("Files", tostring(count_items(pr.files))) end
  if pr.comments ~= nil then b.field("Comments", tostring(count_items(pr.comments))) end
  local mergeable = mergeable_text(pr)
  local mergeable_hl = nil
  if mergeable then
    if mergeable:find("conflict", 1, true) or mergeable:find("dirty", 1, true) then
      mergeable_hl = "DevOpsErr"
    elseif mergeable:find("mergeable", 1, true) or mergeable:find("clean", 1, true) then
      mergeable_hl = "DevOpsOk"
    else
      mergeable_hl = "DevOpsWarn"
    end
  end
  b.field("Mergeable", mergeable, mergeable_hl)
  local pass, fail, pend = checks_summary(pr.statusCheckRollup)
  if pass then
    local parts = {}
    if pass > 0 then parts[#parts + 1] = "✓ " .. pass end
    if fail > 0 then parts[#parts + 1] = "✗ " .. fail end
    if pend > 0 then parts[#parts + 1] = "● " .. pend end
    b.field("Checks", table.concat(parts, "   "), fail > 0 and "DevOpsErr" or "DevOpsOk")
  end
  if type(pr.labels) == "table" and #pr.labels > 0 then
    local names = {}
    for _, l in ipairs(pr.labels) do names[#names + 1] = l.name end
    b.field("Labels", table.concat(names, "  "), "DevOpsLabel")
  end

  if pr.reviews ~= nil or pr.reviewRequests ~= nil then
    local reviewers = review_rows(pr)
    b.divider("Reviewers")
    if #reviewers == 0 then
      local line = b.add("   none")
      b.hl(line, 0, #b.lines()[line], "DevOpsDim")
    else
      for _, reviewer in ipairs(reviewers) do
        local verdict = reviewer.verdict
        local line = b.add(("  %-22s %s"):format(reviewer.name, verdict))
        b.hl(line, 2, 2 + #reviewer.name, "DevOpsDetailTitle")
        b.hl(line, #b.lines()[line] - #verdict, #b.lines()[line], reviewer.hl)
      end
    end
  end

  b.divider("Description")
  local body = (pr.body and pr.body ~= "" and pr.body or "_No description_"):gsub("\r", "")
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    b.add("  " .. line)
  end

  -- Timeline: merge comments, reviews, and commits in chronological order
  local timeline = {}
  for _, c in ipairs(pr.comments or {}) do
    timeline[#timeline + 1] = {
      kind = "comment",
      author = c.author and c.author.login or "?",
      body = c.body or "",
      time = c.createdAt or "",
    }
  end
  for _, r in ipairs(pr.reviews or {}) do
    local rev_body = r.body or ""
    if rev_body ~= "" or (r.state and r.state ~= "PENDING") then
      timeline[#timeline + 1] = {
        kind = "review",
        author = r.author and r.author.login or "?",
        body = rev_body,
        state = r.state or "",
        time = r.createdAt or r.submittedAt or "",
      }
    end
  end
  for _, c in ipairs(pr.commits or {}) do
    local author = "?"
    if c.authors and #c.authors > 0 then author = c.authors[1].login or c.authors[1].name or "?" end
    timeline[#timeline + 1] = {
      kind = "commit",
      author = author,
      body = c.messageHeadline or "",
      oid = c.oid or "",
      time = c.committedDate or c.authoredDate or "",
    }
  end

  table.sort(timeline, function(a, b) return a.time < b.time end)

  if #timeline > 0 then
    b.divider("Activity")
    for _, ev in ipairs(timeline) do
      b.add("")
      local ts = format_time(ev.time)
      if ev.kind == "comment" then
        local hdr = "  💬  " .. ev.author .. "  commented"
        local line = b.add(hdr .. "  " .. ts)
        b.hl(line, #"  💬  ", #"  💬  " + #ev.author, "DevOpsKey")
        b.hl(line, #hdr + 2, #hdr + 2 + #ts, "DevOpsDim")
      elseif ev.kind == "review" then
        local state_label = (ev.state == "APPROVED" and "approved")
          or (ev.state == "CHANGES_REQUESTED" and "requested changes")
          or (ev.state == "COMMENTED" and "reviewed")
          or (ev.state == "DISMISSED" and "dismissed review")
          or "reviewed"
        local state_hl = (ev.state == "APPROVED" and "DevOpsOk")
          or (ev.state == "CHANGES_REQUESTED" and "DevOpsErr")
          or "DevOpsWarn"
        local icon = ev.state == "APPROVED" and "✓" or (ev.state == "CHANGES_REQUESTED" and "✗" or "●")
        local hdr = "  " .. icon .. "  " .. ev.author .. "  " .. state_label
        local line = b.add(hdr .. "  " .. ts)
        b.hl(line, #("  " .. icon .. "  "), #("  " .. icon .. "  ") + #ev.author, "DevOpsKey")
        b.hl(line, #("  " .. icon .. "  " .. ev.author .. "  "), #("  " .. icon .. "  " .. ev.author .. "  ") + #state_label, state_hl)
        b.hl(line, #hdr + 2, #hdr + 2 + #ts, "DevOpsDim")
      elseif ev.kind == "commit" then
        local short_oid = ev.oid:sub(1, 7)
        local hdr = "  ⊙  " .. ev.author .. "  pushed  " .. short_oid
        local line = b.add(hdr .. "  " .. ts)
        b.hl(line, #"  ⊙  ", #"  ⊙  " + #ev.author, "DevOpsKey")
        b.hl(line, #("  ⊙  " .. ev.author .. "  pushed  "), #("  ⊙  " .. ev.author .. "  pushed  ") + #short_oid, "DevOpsId")
        b.hl(line, #hdr + 2, #hdr + 2 + #ts, "DevOpsDim")
      end
      -- Body (truncated for readability)
      if ev.body ~= "" then
        local body_lines = vim.split(ev.body:gsub("\r", ""), "\n", { plain = true })
        local max_lines = 8
        for i, bl in ipairs(body_lines) do
          if i > max_lines then
            local trunc = b.add("    ...")
            b.hl(trunc, 0, #"    ...", "DevOpsDim")
            break
          end
          b.add("    " .. bl)
        end
      end
    end
  end

  return b
end

function M.open_pr(pr)
  local repo = pr.repository and pr.repository.nameWithOwner
  local n = pr.number
  local title = "GitHub · #" .. (n or "?")

  local function setup_keys(buf)
    vim.keymap.set("n", "o", function() vim.ui.open(pr.url) end, { buffer = buf, desc = "Open in browser" })

    if not repo or not n then return end

    -- Approve
    vim.keymap.set("n", "a", function()
      gh.pr_approve(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "approve failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: approved #" .. n, vim.log.levels.INFO)
        M.open_pr(pr)
      end)
    end, { buffer = buf, desc = "Approve" })

    -- Request changes
    vim.keymap.set("n", "R", function()
      input.open("Request changes #" .. n, "", function(body)
        if body == "" then return end
        gh.pr_request_changes(repo, n, body, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "review failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: requested changes on #" .. n, vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, desc = "Request changes" })

    -- Comment
    vim.keymap.set("n", "c", function()
      input.open("Comment #" .. n, "", function(body)
        if body == "" then return end
        gh.pr_comment(repo, n, body, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: commented on #" .. n, vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, desc = "Comment" })

    -- Diff
    vim.keymap.set("n", "d", function()
      gh.pr_diff(repo, n, function(ok, diff_text, err)
        if not ok then return vim.notify("DevOps: " .. (err or "diff failed"), vim.log.levels.ERROR) end
        diff_viewer.open(diff_text, "Diff #" .. n, { pr = { repo = repo, number = n } })
      end)
    end, { buffer = buf, desc = "Diff" })

    -- Mark ready
    vim.keymap.set("n", "D", function()
      gh.pr_ready(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "ready failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: #" .. n .. " marked ready", vim.log.levels.INFO)
        M.open_pr(pr)
      end)
    end, { buffer = buf, desc = "Mark ready" })

    -- Merge
    vim.keymap.set("n", "m", function()
      vim.ui.select({ "Yes, squash merge", "Cancel" }, { prompt = "Merge #" .. n .. "?" }, function(choice)
        if not choice or choice:match("^Cancel") then return end
        gh.pr_merge(repo, n, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "merge failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: #" .. n .. " merged!", vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, desc = "Merge" })

    -- Checkout
    vim.keymap.set("n", "x", function()
      gh.pr_checkout(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "checkout failed — cwd must be the repo"), vim.log.levels.ERROR) end
        vim.notify("DevOps: checked out #" .. n, vim.log.levels.INFO)
      end)
    end, { buffer = buf, desc = "Checkout" })
  end

  -- Show a quick card immediately, then enrich with a full `gh pr view`.
  show(title, build_pr(pr), function(buf)
    setup_keys(buf)
    if repo and n then
      gh.pr_view(repo, n, function(ok, full)
        if not ok or not full then return end
        if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
        full.repository = pr.repository
        full.url = pr.url
        show(title, build_pr(full), setup_keys)
      end)
    end
  end)
end

---------------------------------------------------------------------------
-- Inline detail API — render into an external buffer (nav-stack use).
-- Each returns nothing but calls `on_ready(b, setup_keys_fn)` async.
---------------------------------------------------------------------------

--- Load and render a Jira issue detail. Calls on_ready(b, setup_keys_fn) once
--- the initial data is available, and calls on_update(b, setup_keys_fn) each
--- time async enrichment (comments, linked PRs) arrives.
function M.load_issue(key, opts)
  opts = opts or {}
  local on_ready = opts.on_ready or function() end
  local on_update = opts.on_update or on_ready
  local on_navigate = opts.on_navigate  -- callback(kind, data) for linked-item nav

  api.get_issue(key, function(ok, issue, err)
    if not ok or not issue then
      return vim.notify("DevOps: " .. (err or ("failed to load " .. key)), vim.log.levels.ERROR)
    end
    local project_key = key:match("^(%u+)-")

    local function make_keys(buf)
      local browse = client.base_url() .. "/browse/" .. issue.key
      vim.keymap.set("n", "o", function() vim.ui.open(browse) end, { buffer = buf, nowait = true, desc = "Open in browser" })
      vim.keymap.set("n", "c", function()
        input.open("Comment " .. key, "", function(text)
          if text == "" then return end
          api.add_comment(key, text, function(ok3, _, err3)
            if not ok3 then return vim.notify("DevOps: " .. (err3 or "comment failed"), vim.log.levels.ERROR) end
            vim.notify("DevOps: comment added to " .. key, vim.log.levels.INFO)
            M.load_issue(key, opts)
          end)
        end, { on_mention = jira_mention() })
      end, { buffer = buf, nowait = true, desc = "Comment" })
      vim.keymap.set("n", "e", function()
        api.get_issue(key, function(ok3, iss, err3)
          if not ok3 then return vim.notify("DevOps: " .. (err3 or "fetch failed"), vim.log.levels.ERROR) end
          local f = iss.fields or {}
          vim.ui.input({ prompt = "Summary: ", default = f.summary or "" }, function(new_summary)
            if not new_summary then return end
            local desc_text = table.concat(adf.adf_to_lines(f.description), "\n")
            input.open("Description " .. key, desc_text, function(new_desc)
              local fields = {}
              if new_summary ~= (f.summary or "") then fields.summary = new_summary end
              fields.description = adf.text_to_adf(new_desc)
              api.update_issue(key, fields, function(ok4, _, err4)
                if not ok4 then return vim.notify("DevOps: " .. (err4 or "update failed"), vim.log.levels.ERROR) end
                vim.notify("DevOps: " .. key .. " updated", vim.log.levels.INFO)
                M.load_issue(key, opts)
              end)
            end)
          end)
        end)
      end, { buffer = buf, nowait = true, desc = "Edit" })
      vim.keymap.set("n", "a", function()
        api.assignable_users(project_key, function(ok3, users, err3)
          if not ok3 then return vim.notify("DevOps: " .. (err3 or "user lookup failed"), vim.log.levels.ERROR) end
          local choices = {}
          local me_id = client.account_id()
          if me_id then
            choices[#choices + 1] = { label = "● Me (" .. (client.display_name() or "") .. ")", account_id = me_id }
          end
          choices[#choices + 1] = { label = "✗ Unassigned", account_id = nil }
          for _, u in ipairs(users) do
            if u.accountId and u.accountType ~= "app" then
              choices[#choices + 1] = { label = u.displayName or u.accountId, account_id = u.accountId }
            end
          end
          vim.ui.select(choices, {
            prompt = "Assign " .. key .. " to:",
            format_item = function(c2) return c2.label end,
          }, function(choice)
            if not choice then return end
            api.assign(key, choice.account_id, function(ok4, _, err4)
              if not ok4 then return vim.notify("DevOps: " .. (err4 or "assign failed"), vim.log.levels.ERROR) end
              vim.notify("DevOps: " .. key .. " assigned to " .. choice.label, vim.log.levels.INFO)
              M.load_issue(key, opts)
            end)
          end)
        end)
      end, { buffer = buf, nowait = true, desc = "Assign" })
    end

    local b_initial = build_issue(issue, nil, nil)
    on_ready(b_initial, make_keys)

    -- Async enrichment
    local async_prs, async_comments
    local function rebuild()
      local b_new = build_issue(issue, async_prs, async_comments)
      on_update(b_new, make_keys)
    end
    api.dev_status(issue.id, function(ok2, prs)
      async_prs = ok2 and prs or {}
      rebuild()
    end)
    api.comments(issue.key, function(ok2, cmts)
      async_comments = ok2 and cmts or {}
      rebuild()
    end)
  end)
end

--- Load and render a GitHub PR detail. Calls on_ready(b, setup_keys_fn) once
--- the initial data is available, and on_update when enriched data arrives.
function M.load_pr(pr, opts)
  opts = opts or {}
  local on_ready = opts.on_ready or function() end
  local on_update = opts.on_update or on_ready

  local repo = pr.repository and pr.repository.nameWithOwner
  local n = pr.number

  local function make_keys(buf)
    vim.keymap.set("n", "o", function() vim.ui.open(pr.url) end, { buffer = buf, nowait = true, desc = "Open in browser" })
    if not repo or not n then return end
    vim.keymap.set("n", "a", function()
      gh.pr_approve(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "approve failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: approved #" .. n, vim.log.levels.INFO)
        M.load_pr(pr, opts)
      end)
    end, { buffer = buf, nowait = true, desc = "Approve" })
    vim.keymap.set("n", "R", function()
      input.open("Request changes #" .. n, "", function(body)
        if body == "" then return end
        gh.pr_request_changes(repo, n, body, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "review failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: requested changes on #" .. n, vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, nowait = true, desc = "Request changes" })
    vim.keymap.set("n", "c", function()
      input.open("Comment #" .. n, "", function(body)
        if body == "" then return end
        gh.pr_comment(repo, n, body, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "comment failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: commented on #" .. n, vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, nowait = true, desc = "Comment" })
    vim.keymap.set("n", "d", function()
      gh.pr_diff(repo, n, function(ok, diff_text, err)
        if not ok then return vim.notify("DevOps: " .. (err or "diff failed"), vim.log.levels.ERROR) end
        diff_viewer.open(diff_text, "Diff #" .. n, { pr = { repo = repo, number = n } })
      end)
    end, { buffer = buf, nowait = true, desc = "Diff" })
    vim.keymap.set("n", "D", function()
      gh.pr_ready(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "ready failed"), vim.log.levels.ERROR) end
        vim.notify("DevOps: #" .. n .. " marked ready for review", vim.log.levels.INFO)
        M.load_pr(pr, opts)
      end)
    end, { buffer = buf, nowait = true, desc = "Mark ready" })
    vim.keymap.set("n", "m", function()
      vim.ui.select({ "Yes, squash merge", "Cancel" }, { prompt = "Merge #" .. n .. "?" }, function(choice)
        if not choice or choice:match("^Cancel") then return end
        gh.pr_merge(repo, n, function(ok, _, err)
          if not ok then return vim.notify("DevOps: " .. (err or "merge failed"), vim.log.levels.ERROR) end
          vim.notify("DevOps: #" .. n .. " merged!", vim.log.levels.INFO)
        end)
      end)
    end, { buffer = buf, nowait = true, desc = "Merge" })
    vim.keymap.set("n", "x", function()
      gh.pr_checkout(repo, n, function(ok, _, err)
        if not ok then return vim.notify("DevOps: " .. (err or "checkout failed — cwd must be the repo"), vim.log.levels.ERROR) end
        vim.notify("DevOps: checked out #" .. n, vim.log.levels.INFO)
      end)
    end, { buffer = buf, nowait = true, desc = "Checkout" })
  end

  on_ready(build_pr(pr), make_keys)

  -- Enrich with full PR data
  if repo and n then
    gh.pr_view(repo, n, function(ok, full)
      if not ok or not full then return end
      full.repository = pr.repository
      full.url = pr.url
      on_update(build_pr(full), make_keys)
    end)
  end
end

return M
