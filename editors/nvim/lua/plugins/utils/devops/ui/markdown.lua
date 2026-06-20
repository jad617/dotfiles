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

--- Parse a markdown string into { lines = {}, highlights = {} }
--- Each highlight: { line = 0-idx, col_start, col_end, hl = "group" }
function M.render(text, indent)
  indent = indent or "  "
  local lines = {}
  local highlights = {}
  local in_code_block = false

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
        lines[#lines + 1] = prefix .. header_text
        push_highlight(highlights, #lines - 1, 0, #lines[#lines], "DevOpsMdHeader")
        apply_inline(highlights, #lines - 1, header_text, #prefix)
      elseif bullet_text then
        local prefix = indent .. bullet_indent .. "• "
        lines[#lines + 1] = prefix .. bullet_text
        push_highlight(highlights, #lines - 1, #indent, #prefix, "DevOpsMdListBullet")
        apply_inline(highlights, #lines - 1, bullet_text, #prefix)
      elseif ordered_text then
        local prefix = indent .. ordered_indent .. ordered_num .. ". "
        lines[#lines + 1] = prefix .. ordered_text
        push_highlight(highlights, #lines - 1, #indent, #prefix, "DevOpsMdListBullet")
        apply_inline(highlights, #lines - 1, ordered_text, #prefix)
      else
        lines[#lines + 1] = indent .. line
        apply_inline(highlights, #lines - 1, line, #indent)
      end
    end
  end

  return { lines = lines, highlights = highlights }
end

return M
