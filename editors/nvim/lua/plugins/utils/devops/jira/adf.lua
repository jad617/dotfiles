---------------------------------------------------------------------------
-- Atlassian Document Format (ADF) — bidirectional:
--   • adf_to_lines(adf)   → render ADF to plain text lines (read)
--   • text_to_adf(text)   → convert plain text to minimal ADF (write)
---------------------------------------------------------------------------

local M = {}

-- Inline text of a node (recursive over inline children).
local function node_text(node)
  if type(node) ~= "table" then return "" end
  local t = node.type
  if t == "text" then return node.text or "" end
  if t == "hardBreak" then return "\n" end
  if t == "mention" then return "@" .. ((node.attrs and node.attrs.text) or "") end
  if t == "emoji" then return (node.attrs and (node.attrs.shortName or node.attrs.text)) or "" end
  if t == "inlineCard" then return (node.attrs and node.attrs.url) or "" end

  local parts = {}
  for _, c in ipairs(node.content or {}) do
    parts[#parts + 1] = node_text(c)
  end
  return table.concat(parts)
end

local render_block -- forward declaration

local function render_list(node, out, prefix, ordered)
  local i = 1
  for _, item in ipairs(node.content or {}) do
    local bullet = ordered and (i .. ". ") or "• "
    local sub = {}
    for _, c in ipairs(item.content or {}) do
      render_block(c, sub, "")
    end
    if #sub == 0 then sub = { "" } end
    for idx, line in ipairs(sub) do
      if idx == 1 then
        out[#out + 1] = prefix .. bullet .. line
      else
        out[#out + 1] = prefix .. string.rep(" ", #bullet) .. line
      end
    end
    i = i + 1
  end
end

local function push_text(text, out, prefix)
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    out[#out + 1] = prefix .. line
  end
end

render_block = function(node, out, prefix)
  prefix = prefix or ""
  local t = node.type

  if t == "paragraph" then
    push_text(node_text(node), out, prefix)
  elseif t == "heading" then
    local level = (node.attrs and node.attrs.level) or 1
    out[#out + 1] = prefix .. string.rep("#", level) .. " " .. node_text(node)
  elseif t == "bulletList" then
    render_list(node, out, prefix, false)
  elseif t == "orderedList" then
    render_list(node, out, prefix, true)
  elseif t == "codeBlock" then
    out[#out + 1] = prefix .. "```"
    push_text(node_text(node), out, prefix)
    out[#out + 1] = prefix .. "```"
  elseif t == "blockquote" then
    for _, c in ipairs(node.content or {}) do
      render_block(c, out, prefix .. "> ")
    end
  elseif t == "rule" then
    out[#out + 1] = prefix .. string.rep("─", 40)
  elseif t == "mediaGroup" or t == "mediaSingle" then
    out[#out + 1] = prefix .. "[media]"
  elseif t == "table" then
    out[#out + 1] = prefix .. "[table omitted]"
  else
    local text = node_text(node)
    if text ~= "" then push_text(text, out, prefix) end
  end
end

---------------------------------------------------------------------------
-- Write direction: plain text → ADF document (paragraphs only for v1).
---------------------------------------------------------------------------

-- Parse a line into a list of ADF inline nodes, handling @[Name]{accountId}
-- mention markers alongside plain text.
local function parse_inline(line)
  local nodes = {}
  local pos = 1
  while pos <= #line do
    -- Look for @[Name]{accountId} pattern
    local ms, me, name, aid = line:find("@%[(.-)%]%{(.-)%}", pos)
    if ms then
      -- Plain text before the mention
      if ms > pos then
        nodes[#nodes + 1] = { type = "text", text = line:sub(pos, ms - 1) }
      end
      -- ADF mention node
      nodes[#nodes + 1] = {
        type = "mention",
        attrs = { id = aid, text = "@" .. name, accessLevel = "" },
      }
      pos = me + 1
    else
      -- Rest of line is plain text
      nodes[#nodes + 1] = { type = "text", text = line:sub(pos) }
      break
    end
  end
  return nodes
end

-- Convert plain text into a minimal ADF document. Blank lines become empty
-- paragraphs; each non-blank line becomes a paragraph with text/mention nodes.
-- Mention syntax: @[Display Name]{accountId} is converted to ADF mention nodes.
function M.text_to_adf(text)
  local content = {}
  for _, line in ipairs(vim.split(text or "", "\n", { plain = true })) do
    if line == "" then
      content[#content + 1] = { type = "paragraph", content = {} }
    else
      content[#content + 1] = { type = "paragraph", content = parse_inline(line) }
    end
  end
  if #content == 0 then content = { { type = "paragraph" } } end
  return { type = "doc", version = 1, content = content }
end

---------------------------------------------------------------------------
-- Read direction: ADF → plain text lines.
---------------------------------------------------------------------------

-- Accepts an ADF document table (with .content) or a plain string.
-- Returns a list of string lines.
function M.adf_to_lines(adf)
  if type(adf) == "string" then return vim.split(adf, "\n", { plain = true }) end
  if type(adf) ~= "table" then return { "" } end

  local out = {}
  for _, node in ipairs(adf.content or {}) do
    render_block(node, out, "")
  end
  if #out == 0 then out = { "" } end
  return out
end

return M
