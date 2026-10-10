---------------------------------------------------------------------------
-- Multiline input — scratch float for composing comments/descriptions.
-- <C-s> submits (normal or insert), q/Esc cancels (normal only).
-- @    inserts a @mention in normal mode (when on_mention is provided).
---------------------------------------------------------------------------

local M = {}

local ns_mention = vim.api.nvim_create_namespace("devops_input_mention")

--- Insert text at cursor position in the given buffer/window.
local function insert_at_cursor(buf, win, text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { before .. text .. after })
  vim.api.nvim_win_set_cursor(win, { row, col + #text })
end

local ns_preview = vim.api.nvim_create_namespace("devops_input_preview")

local PREVIEW_EXTMARK_KEYS = { "end_row", "end_col", "hl_group", "line_hl_group", "hl_eol", "priority" }

--- Copy `ns` extmarks of buf rows [first, last] (0-based) into a preview spec,
--- rebased so `first` becomes row 0.
function M.extmarks_from(buf, ns, first, last)
  local out = {}
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { first, 0 }, { last, -1 }, { details = true })
  for _, m in ipairs(marks) do
    local d, o = m[4] or {}, {}
    for _, k in ipairs(PREVIEW_EXTMARK_KEYS) do o[k] = d[k] end
    if o.end_row then
      if o.end_row > last then o.end_row, o.end_col = last, nil end
      o.end_row = o.end_row - first
    end
    out[#out + 1] = { m[2] - first, m[3], o }
  end
  return out
end

-- Read-only float stacked above the input showing what is being commented on.
local function open_preview(p, geo)
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, p.lines)
  for _, m in ipairs(p.extmarks or {}) do
    pcall(vim.api.nvim_buf_set_extmark, pbuf, ns_preview, m[1], m[2], m[3])
  end
  if p.focus then
    pcall(vim.api.nvim_buf_set_extmark, pbuf, ns_preview, p.focus - 1, 0, {
      sign_text = "▶", sign_hl_group = "DevOpsInputBorder",
    })
  end
  if p.filetype then vim.bo[pbuf].filetype = p.filetype end
  vim.bo[pbuf].modifiable = false
  local pwin = vim.api.nvim_open_win(pbuf, false, vim.tbl_extend("force", geo, {
    style = "minimal", border = "rounded",
    title = " " .. (p.title or "Preview") .. " ", title_pos = "center",
    footer = " <S-Up>/<S-Down> switch ", footer_pos = "right",
  }))
  vim.wo[pwin].winhighlight = "FloatBorder:DevOpsInputPreviewBorder,FloatTitle:DevOpsInputTitle,FloatFooter:DevOpsInputPreviewBorder,CursorLine:Visual"
  vim.wo[pwin].wrap = p.wrap ~= false
  vim.wo[pwin].linebreak = true
  vim.wo[pwin].signcolumn = p.focus and "yes:1" or "no"
  vim.wo[pwin].scrolloff = 0
  pcall(function() vim.wo[pwin].scrolloffpad = 0 end)
  if p.focus then
    vim.wo[pwin].cursorline = true
    -- Show the focus line roughly centred, but never leave empty rows at the
    -- bottom: if the rest of the text fits, pin the last line to the bottom.
    -- Works in screen rows, so wrapped lines are accounted for.
    local function focus()
      if not vim.api.nvim_win_is_valid(pwin) then return end
      local h = vim.api.nvim_win_get_height(pwin)
      local n = vim.api.nvim_buf_line_count(pbuf)
      vim.api.nvim_win_call(pwin, function()
        vim.api.nvim_win_set_cursor(pwin, { p.focus, 0 })
        vim.cmd("normal! zz")
        local top = vim.fn.line("w0")
        if vim.api.nvim_win_text_height(pwin, { start_row = top - 1 }).all < h then
          vim.api.nvim_win_set_cursor(pwin, { n, 0 })
          vim.cmd("normal! zb")
          vim.api.nvim_win_set_cursor(pwin, { p.focus, 0 })
        end
      end)
    end
    focus()
    -- Something in the event loop resets a fresh unfocused float's cursor;
    -- re-apply once things settle.
    vim.schedule(focus)
    vim.defer_fn(focus, 50)
  end
  return pwin, pbuf
end

--- Open a scratch float for multiline text input.
--- @param title string  Window title shown in the border
--- @param initial string|nil  Pre-filled text (newline-separated)
--- @param on_submit fun(text: string)  Called with the buffer text on submit
--- @param opts table|nil  Optional:
---   on_mention = fun(insert_fn)
---   parent_win = integer, compact = boolean  (anchor to the bottom of a window)
---   preview = { title, lines, extmarks = { {row0, col0, extmark_opts} },
---               focus = row1, filetype, wrap }  (read-only float above the input)
---   draft_key = string  (defaults to the title for new text; false disables).
---     Cancelling keeps the text as a draft; it's restored on the next open.
function M.open(title, initial, on_submit, opts)
  opts = opts or {}
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "devops_input"

  -- Drafts only for new text (edits start from the existing body).
  local store = require("plugins.utils.devops.store")
  local draft_key = opts.draft_key
  if draft_key == nil and (initial or "") == "" then draft_key = title end
  local initial_text = initial or ""
  local restored = false
  if draft_key then
    local d = store.load_drafts()[draft_key]
    if d and d.text then initial, restored = d.text, true end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial or "", "\n", { plain = true }))

  local hint = "<C-s> submit, q cancel" .. (draft_key and " → draft" or "")
  if restored then hint = "draft restored · " .. hint end
  if opts.on_mention then hint = hint .. ", @ mention" end

  local preview = opts.preview
  if preview and (not preview.lines or #preview.lines == 0) then preview = nil end
  -- Screen rows the preview needs at `width` (wrapped lines take several).
  local function preview_rows(width)
    local text_w = math.max(1, width - (preview.focus and 2 or 0))
    if preview.wrap == false then return #preview.lines end
    local rows = 0
    for _, l in ipairs(preview.lines) do
      rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / text_w))
    end
    return rows
  end

  -- Size relative to parent window (content pane) if provided, else editor
  local parent_win = opts.parent_win
  local w, h, float_row, float_col, prev_h, prev_row
  if parent_win and vim.api.nvim_win_is_valid(parent_win) then
    local pw = vim.api.nvim_win_get_width(parent_win)
    local ph = vim.api.nvim_win_get_height(parent_win)
    w = pw - 2 -- full width minus border
    local divisor = opts.compact and 4 or 2
    h = math.floor(ph / divisor)
    float_row = ph - h -- anchored to bottom
    float_col = 0
    if preview then
      prev_h = math.min(preview_rows(w), 15, float_row - 2)
      prev_row = float_row - prev_h - 2
    end
  else
    w = math.floor(vim.o.columns * 0.6)
    h = math.floor(vim.o.lines * 0.4)
    float_col = math.floor((vim.o.columns - w) / 2)
    if preview then
      prev_h = math.min(preview_rows(w), math.floor(vim.o.lines * 0.3))
      prev_row = math.max(0, math.floor((vim.o.lines - (prev_h + h + 4)) / 2))
      float_row = prev_row + prev_h + 2
    else
      float_row = math.floor((vim.o.lines - h) / 2)
    end
    parent_win = nil
  end

  local relative = parent_win and { relative = "win", win = parent_win } or { relative = "editor" }
  local win_config = vim.tbl_extend("force", relative, {
    width = w,
    height = h,
    row = float_row,
    col = float_col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " (" .. hint .. ") ",
    title_pos = "center",
  })

  vim.api.nvim_set_hl(0, "DevOpsInputPreviewBorder", { link = "Comment", default = true })
  local pwin
  if preview and prev_h and prev_h >= 1 then
    pwin = open_preview(preview, vim.tbl_extend("force", relative, {
      width = w, height = prev_h, row = prev_row, col = float_col,
    }))
  end

  local win = vim.api.nvim_open_win(buf, true, win_config)

  -- Colors: sage green text, orange border, purple title, yellow mentions
  vim.api.nvim_set_hl(0, "DevOpsInputNormal", { fg = "#99bc80" })
  vim.api.nvim_set_hl(0, "DevOpsInputBorder", { fg = "#ff9e64" })
  vim.api.nvim_set_hl(0, "DevOpsInputTitle", { fg = "#c27fd7", bold = true })
  vim.api.nvim_set_hl(0, "DevOpsMention", { fg = "#e5c07b", bold = true })
  vim.wo[win].winhighlight = "Normal:DevOpsInputNormal,FloatBorder:DevOpsInputBorder,FloatTitle:DevOpsInputTitle"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Place cursor at the end of the last line and enter insert mode.
  local line_count = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""
  vim.api.nvim_win_set_cursor(win, { line_count, #last_line })
  vim.cmd("startinsert!")

  -- Disable nvim-cmp in comment input to avoid stealing BS/CR/Tab
  local cmp_ok, cmp = pcall(require, "cmp")
  if cmp_ok then cmp.setup.buffer({ enabled = false }) end

  -- Mention tracking: display @Name but store name→id mapping for submission
  local mentions = {} -- { name = accountId }
  -- Each mention's extmark id → name, for atomic delete
  local mention_marks = {} -- { extmark_id = name }

  local function place_mention_marks()
    -- Clear old marks and re-scan for mention positions
    for mid, _ in pairs(mention_marks) do
      pcall(vim.api.nvim_buf_del_extmark, buf, ns_mention, mid)
    end
    mention_marks = {}
    vim.api.nvim_buf_clear_namespace(buf, ns_mention, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for i, line in ipairs(lines) do
      for name, _ in pairs(mentions) do
        local token = "@" .. name
        local s, e = line:find(token, 1, true) -- plain find for names with special chars
        while s do
          local mid = vim.api.nvim_buf_set_extmark(buf, ns_mention, i - 1, s - 1, {
            end_row = i - 1,
            end_col = e,
            hl_group = "DevOpsMention",
          })
          mention_marks[mid] = name
          s, e = line:find(token, e + 1, true)
        end
      end
    end
  end

  -- Re-highlight on text changes + guard: if a mention is partially deleted, nuke it
  local cleaning = false
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = buf,
    callback = function()
      if cleaning then return end
      local full = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      for name, _ in pairs(mentions) do
        local token = "@" .. name
        if not full:find(token, 1, true) then
          -- Mention is broken. Find and remove the leftover on any line.
          cleaning = true
          mentions[name] = nil
          for i = 1, vim.api.nvim_buf_line_count(buf) do
            local line = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
            -- Find longest prefix of token still in the line
            for len = #token - 1, 1, -1 do
              local prefix = token:sub(1, len)
              local fs, fe = line:find(prefix, 1, true)
              if fs then
                -- Also eat trailing space
                if line:sub(fe + 1, fe + 1) == " " then fe = fe + 1 end
                local before = line:sub(1, fs - 1)
                local after = line:sub(fe + 1)
                vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { before .. after })
                -- Fix cursor position
                local r, c = unpack(vim.api.nvim_win_get_cursor(win))
                if r == i and c > fs - 1 then
                  pcall(vim.api.nvim_win_set_cursor, win, { r, math.max(fs - 1, 0) })
                end
                cleaning = false
                place_mention_marks()
                return
              end
            end
            -- Also check if just the name (without @) remains
            local ns2, ne2 = line:find(name, 1, true)
            if ns2 then
              if line:sub(ne2 + 1, ne2 + 1) == " " then ne2 = ne2 + 1 end
              local before = line:sub(1, ns2 - 1)
              local after = line:sub(ne2 + 1)
              vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { before .. after })
              local r, c = unpack(vim.api.nvim_win_get_cursor(win))
              if r == i and c > ns2 - 1 then
                pcall(vim.api.nvim_win_set_cursor, win, { r, math.max(ns2 - 1, 0) })
              end
              cleaning = false
              place_mention_marks()
              return
            end
          end
          cleaning = false
        end
      end
      place_mention_marks()
    end,
  })

  -- Atomic backspace: if cursor is inside/at-end of a mention, delete whole token
  local function atomic_backspace()
    local row, col = unpack(vim.api.nvim_win_get_cursor(win))
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""

    -- Check if cursor is inside or just after any known @Name mention
    for name, _ in pairs(mentions) do
      local token = "@" .. name
      local s, e = line:find(token, 1, true)
      while s do
        -- col is 0-indexed; s/e are 1-indexed
        -- Include trailing space: if char after match is space, extend range
        local range_end = e
        if line:sub(e + 1, e + 1) == " " then range_end = e + 1 end
        -- Cursor anywhere from inside the @ to just past trailing space
        if col >= s and col <= range_end then
          local before = line:sub(1, s - 1)
          local after = line:sub(range_end + 1)
          vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { before .. after })
          vim.api.nvim_win_set_cursor(win, { row, math.min(s - 1, #(before .. after)) })
          -- Remove from mentions if gone from full text
          local full = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
          if not full:find(token, 1, true) then mentions[name] = nil end
          place_mention_marks()
          return
        end
        s, e = line:find(token, e + 1, true)
      end
    end
    -- Default backspace
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", false)
  end

  vim.keymap.set("i", "<BS>", atomic_backspace, { buffer = buf, nowait = true, desc = "Atomic mention delete" })

  local closed = false
  local function do_close(submitted)
    if closed then return end
    closed = true
    if draft_key and vim.api.nvim_buf_is_valid(buf) then
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      -- Untouched prefill (e.g. "@author ") isn't worth keeping.
      local keep = submitted ~= true and text ~= initial_text
      pcall(store.set_draft, draft_key, keep and text or "")
    end
    vim.cmd("stopinsert")
    if pwin and vim.api.nvim_win_is_valid(pwin) then vim.api.nvim_win_close(pwin, true) end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  local function submit()
    if closed then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    -- Replace @Name with @[Name]{id} for ADF parsing (plain string replace)
    for name, id in pairs(mentions) do
      local token = "@" .. name
      local replacement = "@[" .. name .. "]{" .. id .. "}"
      -- Plain string replace (no pattern)
      local s, e = text:find(token, 1, true)
      while s do
        text = text:sub(1, s - 1) .. replacement .. text:sub(e + 1)
        s, e = text:find(token, s + #replacement, true)
      end
    end
    vim.cmd("stopinsert")
    do_close(true)
    on_submit(text)
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "Submit" })
  vim.keymap.set("n", "q", do_close, { buffer = buf, desc = "Cancel" })
  vim.keymap.set({ "n", "i" }, "<C-c>", do_close, { buffer = buf, desc = "Cancel" })
  vim.keymap.set("n", "<C-d>", do_close, { buffer = buf, desc = "Cancel" })
  vim.keymap.set("n", "<Esc>", do_close, { buffer = buf, desc = "Cancel" })

  -- Shift+Up/Down: preview ⇄ input; other directions / edges go to WezTerm.
  local pane_nav = require("plugins.utils.devops.ui.pane_nav")
  local panes = { v = function() return { pwin, win } end }
  pane_nav.map(buf, panes)
  if pwin then
    local pbuf = vim.api.nvim_win_get_buf(pwin)
    pane_nav.map(pbuf, panes)
    local function back() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end end
    for _, k in ipairs({ "q", "<Esc>", "i", "a" }) do
      vim.keymap.set("n", k, back, { buffer = pbuf, nowait = true, desc = "Back to input" })
    end
    vim.keymap.set("n", "<C-s>", submit, { buffer = pbuf, desc = "Submit" })
    vim.keymap.set("n", "<C-c>", do_close, { buffer = pbuf, desc = "Cancel" })
    -- Closing the input any other way (:q, <C-w>c) takes the preview with it.
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(pwin) then vim.api.nvim_win_close(pwin, true) end
        end)
      end,
    })
  end

  -- Mention support: @ in normal or insert mode triggers the user picker.
  if opts.on_mention then
    vim.keymap.set({ "n", "i" }, "@", function()
      local was_insert = vim.fn.mode():sub(1, 1) == "i"
      if was_insert then vim.cmd("stopinsert") end
      opts.on_mention(function(name, id)
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
          mentions[name] = id
          insert_at_cursor(buf, win, "@" .. name .. " ")
          place_mention_marks()
          if was_insert then vim.cmd("startinsert!") end
        end
      end)
    end, { buffer = buf, nowait = true, desc = "Insert @mention" })
  end
end

return M
