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
    while dw(cur) > max do -- a single word longer than the line: hard-break
      local cut = #cur
      while cut > 1 and dw(cur:sub(1, cut)) > max do cut = cut - 1 end
      out[#out + 1] = cur:sub(1, cut)
      cur = cur:sub(cut + 1)
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end

--- Parse a markdown string into { lines = {}, highlights = {} }
--- Each highlight: { line = 0-idx, col_start, col_end, hl = "group" }
--- If `width` (display columns) is given, body text is word-wrapped to it with a
--- hanging indent under list/header markers. Table rows pass through unwrapped.
function M.render(text, indent, width)
  indent = indent or "  "
  local lines = {}
  local highlights = {}
  local in_code_block = false
  local dw = vim.fn.strdisplaywidth

  -- Emit `content` after `prefix` (continuation lines use `hanging`), wrapping to
  -- `width` when set. line_hl spans the whole line; prefix_hl spans the marker.
  local function emit(prefix, hanging, content, line_hl, prefix_hl)
    local is_table = content:match("^%s*|.+|%s*$") ~= nil
    local segs = (width and content ~= "" and not is_table)
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

  for _, raw in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local line = raw:gsub("\r", "")

    if line:match("^%s*```") then
      if in_code_block then
        in_code_block = false
      else
        in_code_block = true
        lines[#lines + 1] = indent .. "───────────────────"
        push_highlight(highlights, #lines - 1, 0, #lines[#lines], "DevOpsMdCodeBlock")
      end
    elseif in_code_block then
      lines[#lines + 1] = indent .. "  " .. line
      push_highlight(highlights, #lines - 1, 0, #lines[#lines], "DevOpsMdCodeBlock")
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
    end
  end

  return { lines = lines, highlights = highlights }
end

return M
