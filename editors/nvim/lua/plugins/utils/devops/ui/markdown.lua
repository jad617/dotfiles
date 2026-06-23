---------------------------------------------------------------------------
-- Markdown → styled Neovim lines with highlight ranges.
-- Supports: headers, bold, italic, inline code, code blocks, lists.
---------------------------------------------------------------------------

local M = {}

local function push_highlight(highlights, line, col_start, col_end, hl)
  if col_end > col_start then
    highlights[#highlights + 1] = {
      line = line,
      col_start = col_start,
      col_end = col_end,
      hl = hl,
    }
  end
end

local function apply_pattern(highlights, line, text, offset, pattern, hl)
  local pos = 1
  while true do
    local s, e = text:find(pattern, pos)
    if not s then return end
    push_highlight(highlights, line, offset + s - 1, offset + e, hl)
    pos = e + 1
  end
end

local function apply_inline(highlights, line, text, offset)
  apply_pattern(highlights, line, text, offset, "`[^`]+`", "DevOpsMdCode")
  apply_pattern(highlights, line, text, offset, "%*%*[^%*]+%*%*", "DevOpsMdBold")
  apply_pattern(highlights, line, text, offset, "__[^_]+__", "DevOpsMdBold")
  apply_pattern(highlights, line, text, offset, "%f[%S]%*[^%*]+%*%f[%W]", "DevOpsMdItalic")
  apply_pattern(highlights, line, text, offset, "%f[%S]_[^_]+_%f[%W]", "DevOpsMdItalic")
end

-- Common HTML entities that show up in GitHub/bot comments.
local ENTITIES = {
  ["&nbsp;"] = " ", ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">",
  ["&quot;"] = '"', ["&#39;"] = "'", ["&apos;"] = "'", ["&mdash;"] = "—",
  ["&ndash;"] = "–", ["&hellip;"] = "…", ["&rarr;"] = "→", ["&larr;"] = "←",
  ["&bull;"] = "•", ["&copy;"] = "©", ["&reg;"] = "®", ["&trade;"] = "™",
  ["&check;"] = "✓", ["&times;"] = "✕",
}

--- Strip HTML/markdown noise so bot comments (swarmia, sonarqube, copilot, …)
--- read cleanly in the TUI: drop HTML comments, convert <br> to newlines, remove
--- images/badges, flatten links to their text, strip tags + bold markers, decode
--- entities, and collapse blank runs.
function M.clean(text)
  if not text or text == "" then return "" end
  local t = text:gsub("\r", "")
  t = t:gsub("<!%-%-.-%-%->", "")                                   -- HTML comments
  t = t:gsub("<[bB][rR]%s*/?>", "\n")                              -- <br> → newline
  t = t:gsub("%[!%[([^%]]*)%]%([^%)]*%)%]%([^%)]*%)", "%1")        -- [![alt](img)](link) → alt
  t = t:gsub("!%[([^%]]*)%]%([^%)]*%)", "%1")                      -- ![alt](img) → alt
  t = t:gsub("%[([^%]]*)%]%([^%)]*%)", "%1")                       -- [text](url) → text
  t = t:gsub('<img[^>]-alt="([^"]*)"[^>]->', "%1")                -- <img alt="x"> → x
  t = t:gsub("<[^>]->", "")                                        -- remaining HTML tags
  t = t:gsub("%*%*([^%*]+)%*%*", "%1")                             -- **bold** → bold
  t = t:gsub("__([^_]+)__", "%1")                                  -- __bold__ → bold
  for ent, ch in pairs(ENTITIES) do t = t:gsub(ent, ch) end
  t = t:gsub("&#(%d+);", function(n) return vim.fn.nr2char(tonumber(n)) end)
  t = t:gsub("[ \t]+\n", "\n")                                    -- trailing spaces
  t = t:gsub("\n\n\n+", "\n\n")                                   -- collapse blank runs
  return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Word-wrap a string to a max display width, breaking on spaces.
local function wrap_words(text, max)
  local dw = vim.fn.strdisplaywidth
  if max < 8 then max = 8 end
  if text == "" or dw(text) <= max then return { text } end
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif dw(cur .. " " .. word) <= max then
      cur = cur .. " " .. word
    else
      out[#out + 1] = cur
      cur = word
    end
    while dw(cur) > max do -- a single word longer than the line
      local cut = #cur
      while cut > 1 and dw(cur:sub(1, cut)) > max do cut = cut - 1 end
      -- Prefer breaking after a separator (dotted identifiers, paths, URLs).
      local brk = cur:sub(1, cut):match(".*[%./_:%-]()")
      if brk and brk > math.floor(cut / 2) then cut = brk - 1 end
      out[#out + 1] = cur:sub(1, cut)
      cur = cur:sub(cut + 1)
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end

-- Split a markdown table row "| a | b |" into trimmed cells (backticks dropped).
local function table_cells(line)
  local s = line:gsub("^%s*|", ""):gsub("|%s*$", "")
  local cells = {}
  for cell in (s .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = (cell:gsub("`", ""):gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return cells
end

-- A separator row like |:---|---:|:--:| (only pipes/colons/dashes/spaces).
local function is_table_sep(line)
  return line:match("^%s*|?[ :|%-]+|?%s*$") ~= nil and line:find("%-") ~= nil
end

--- Parse a markdown string into { lines = {}, highlights = {} }
--- Each highlight: { line = 0-idx, col_start, col_end, hl = "group" }
--- If `width` (display columns) is given, body text is word-wrapped to it with a
--- hanging indent under list/header markers, and tables are aligned to columns
--- (shrinking + wrapping the widest column) so they fit the width.
function M.render(text, indent, width)
  indent = indent or "  "
  local lines = {}
  local highlights = {}
  local in_code_block = false
  local dw = vim.fn.strdisplaywidth

  -- Emit `content` after `prefix` (continuation lines use `hanging`), wrapping to
  -- `width` when set. line_hl spans the whole line; prefix_hl spans the marker.
  local function emit(prefix, hanging, content, line_hl, prefix_hl)
    local segs = (width and content ~= "")
      and wrap_words(content, width - dw(prefix)) or { content }
    for si, seg in ipairs(segs) do
      local pfx = (si == 1) and prefix or hanging
      local full = pfx .. seg
      lines[#lines + 1] = full
      local lidx = #lines - 1
      if line_hl then push_highlight(highlights, lidx, 0, #full, line_hl) end
      if prefix_hl and si == 1 then push_highlight(highlights, lidx, #indent, #prefix, prefix_hl) end
      apply_inline(highlights, lidx, seg, #pfx)
    end
  end

  -- Render an aligned table: shrink the widest column (then wrap its cells) until
  -- the whole row fits `width`. A dim underline separates the header.
  local function render_table(rows, aligns)
    local ncol = 0
    for _, r in ipairs(rows) do ncol = math.max(ncol, #r) end
    if ncol == 0 then return end
    local cw = {}
    for c = 1, ncol do
      local m = 3
      for _, r in ipairs(rows) do m = math.max(m, dw(r[c] or "")) end
      cw[c] = m
    end
    local gap = 2
    local avail = (width or 80) - dw(indent)
    local function total() local t = (ncol - 1) * gap; for c = 1, ncol do t = t + cw[c] end; return t end
    local guard = 0
    while total() > avail and guard < 1000 do
      guard = guard + 1
      local wc, wmax = 1, -1
      for c = 1, ncol do if cw[c] > wmax then wmax, wc = cw[c], c end end
      if cw[wc] <= 6 then break end
      cw[wc] = cw[wc] - 1
    end
    local function pad(seg, w, align)
      local extra = w - dw(seg)
      if extra < 0 then extra = 0 end
      if align == "right" then return string.rep(" ", extra) .. seg end
      if align == "center" then local l = math.floor(extra / 2); return string.rep(" ", l) .. seg .. string.rep(" ", extra - l) end
      return seg .. string.rep(" ", extra)
    end
    for ri, r in ipairs(rows) do
      local wrapped, maxln = {}, 1
      for c = 1, ncol do
        wrapped[c] = wrap_words(r[c] or "", cw[c])
        maxln = math.max(maxln, #wrapped[c])
      end
      for ln = 1, maxln do
        local parts = {}
        for c = 1, ncol do parts[c] = pad(wrapped[c][ln] or "", cw[c], aligns[c]) end
        local full = indent .. table.concat(parts, string.rep(" ", gap))
        lines[#lines + 1] = full
        if ri == 1 then push_highlight(highlights, #lines - 1, 0, #full, "DevOpsMdHeader") end
      end
      if ri == 1 then
        local sep = {}
        for c = 1, ncol do sep[c] = string.rep("─", cw[c]) end
        local full = indent .. table.concat(sep, string.rep(" ", gap))
        lines[#lines + 1] = full
        push_highlight(highlights, #lines - 1, 0, #full, "DevOpsDim")
      end
    end
  end

  local raw_lines = vim.split(text or "", "\n", { plain = true })
  local i = 1
  while i <= #raw_lines do
    local line = raw_lines[i]:gsub("\r", "")
    local next_line = raw_lines[i + 1] and raw_lines[i + 1]:gsub("\r", "") or nil

    if line:match("^%s*```") then
      if in_code_block then
        in_code_block = false
      else
        in_code_block = true
        lines[#lines + 1] = indent .. "───────────────────"
        push_highlight(highlights, #lines - 1, 0, #lines[#lines], "DevOpsMdCodeBlock")
      end
      i = i + 1
    elseif in_code_block then
      lines[#lines + 1] = indent .. "  " .. line
      push_highlight(highlights, #lines - 1, 0, #lines[#lines], "DevOpsMdCodeBlock")
      i = i + 1
    elseif line:match("^%s*|.+|%s*$") and next_line and is_table_sep(next_line) then
      -- Markdown table: collect header + all body rows, then render aligned.
      local aligns = {}
      for _, cell in ipairs(table_cells(next_line)) do
        local l, rr = cell:match("^:"), cell:match(":$")
        aligns[#aligns + 1] = (l and rr and "center") or (rr and "right") or "left"
      end
      local rows = { table_cells(line) }
      local j = i + 2
      while raw_lines[j] and raw_lines[j]:gsub("\r", ""):match("^%s*|.+|%s*$") do
        rows[#rows + 1] = table_cells(raw_lines[j]:gsub("\r", ""))
        j = j + 1
      end
      render_table(rows, aligns)
      i = j
    else
      local hashes, header_text = line:match("^(#+)%s+(.*)")
      local bullet_indent, bullet_text = line:match("^(%s*)[%-%*%+]%s+(.*)")
      local ordered_indent, ordered_num, ordered_text = line:match("^(%s*)(%d+)[%.%)]%s+(.*)")

      if hashes then
        local prefix = indent .. string.rep("▌", #hashes) .. " "
        emit(prefix, string.rep(" ", dw(prefix)), header_text, "DevOpsMdHeader", nil)
      elseif bullet_text then
        local prefix = indent .. bullet_indent .. "• "
        emit(prefix, string.rep(" ", dw(prefix)), bullet_text, nil, "DevOpsMdListBullet")
      elseif ordered_text then
        local prefix = indent .. ordered_indent .. ordered_num .. ". "
        emit(prefix, string.rep(" ", dw(prefix)), ordered_text, nil, "DevOpsMdListBullet")
      else
        emit(indent, indent, line, nil, nil)
      end
      i = i + 1
    end
  end

  return { lines = lines, highlights = highlights }
end

return M
