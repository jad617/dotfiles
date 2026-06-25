---------------------------------------------------------------------------
-- PR changed-files browser built on Snacks.picker.
-- A flat, fuzzy-searchable list of the PR's changed files on the left with a
-- live diff preview on the right (native, smooth navigation). ↵ opens the full
-- diff viewer (split / blame / inline comments) positioned on that file.
--
-- This is the preferred file browser; the diff viewer's homemade tree pane is
-- kept (toggle with 'f' inside the viewer) but off by default.
---------------------------------------------------------------------------

local diff_viewer = require("plugins.utils.devops.ui.diff_viewer")

local M = {}

-- Split a raw unified diff into one block per file. Files are delimited by
-- `diff --git` — the same boundary parse_diff() uses, so block i lines up with
-- the diff viewer's file index i.
local function split_by_file(diff_text)
  local blocks, cur = {}, nil
  for _, line in ipairs(vim.split(diff_text or "", "\n", { plain = true })) do
    if line:match("^diff %-%-git ") then
      local old_path, new_path = line:match("^diff %-%-git a/(.-) b/(.-)$")
      cur = { path = new_path or old_path or line, lines = { line } }
      blocks[#blocks + 1] = cur
    elseif cur then
      cur.lines[#cur.lines + 1] = line
    end
  end
  for _, b in ipairs(blocks) do b.diff = table.concat(b.lines, "\n") end
  return blocks
end

local function format_item(item)
  local dir = vim.fs.dirname(item.text)
  local name = vim.fs.basename(item.text)
  local ret = {}
  if dir and dir ~= "." and dir ~= "" then
    ret[#ret + 1] = { dir .. "/", "SnacksPickerDir" }
  end
  ret[#ret + 1] = { name, "SnacksPickerFile" }
  return ret
end

--- Open the changed-files picker for a PR.
--- @param repo string       "owner/repo"
--- @param n number          PR number
--- @param diff_text string  Raw unified diff (as from `gh pr diff`)
function M.open(repo, n, diff_text)
  if not (Snacks and Snacks.picker) then
    return vim.notify("DevOps: Snacks.picker not available", vim.log.levels.ERROR)
  end
  local blocks = split_by_file(diff_text)
  if #blocks == 0 then
    return vim.notify("DevOps: no changed files in #" .. n, vim.log.levels.INFO)
  end

  local items = {}
  for i, b in ipairs(blocks) do
    items[#items + 1] = {
      idx = i,
      text = b.path,
      file = b.path,
      diff = b.diff,
    }
  end

  Snacks.picker.pick({
    source = "devops_pr_files",
    title = "PR #" .. n .. " · " .. #items .. " files",
    items = items,
    format = format_item,
    -- Dock as a left split (file-tree style), not a centered float — same preset
    -- the file explorer uses; the diff preview renders in the main window.
    layout = { preset = "sidebar" },
    -- Render the file's diff directly (the file may not be checked out, so the
    -- default file previewer can't read it from disk).
    preview = function(ctx)
      ctx.preview:set_lines(vim.split(ctx.item.diff or "", "\n", { plain = true }))
      ctx.preview:highlight({ ft = "diff" })
      ctx.preview:set_title(ctx.item.text)
      return true
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      diff_viewer.open(diff_text, "Diff #" .. n, {
        pr = { repo = repo, number = n },
        focus_file = item.idx,
      })
    end,
  })
end

return M
