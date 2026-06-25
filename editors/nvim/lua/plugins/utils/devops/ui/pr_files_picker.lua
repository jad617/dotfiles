---------------------------------------------------------------------------
-- PR changed-files tree, built on Snacks.picker.
--
-- A directory-nested tree of the PR's changed files. It is purely a navigator:
-- ↵ opens the *normal* diff viewer positioned on that file. No diff preview of
-- its own — the diff is shown by the original viewer ('d'), unchanged.
--
-- It floats (the DevOps dashboard/detail are themselves floats, and a real split
-- would render behind them, invisible).
---------------------------------------------------------------------------

local diff_viewer = require("plugins.utils.devops.ui.diff_viewer")

local M = {}

-- Build a flattened, pre-expanded directory tree from a list of { path, file_idx }.
local function build_tree_items(files)
  local root = { children = {}, order = {} }
  for _, f in ipairs(files) do
    local parts = vim.split(f.path, "/", { plain = true })
    local node = root
    for i = 1, #parts - 1 do
      local seg = parts[i]
      if not node.children[seg] then
        node.children[seg] = { name = seg, dir = true, children = {}, order = {} }
        node.order[#node.order + 1] = seg
      end
      node = node.children[seg]
    end
    local fname = parts[#parts]
    -- NB: snacks reserves `item.idx` (it overwrites it with the picker list
    -- position), so the diff file index is carried as `file_idx`.
    node.children[fname] = { name = fname, dir = false, file_idx = f.file_idx, path = f.path }
    node.order[#node.order + 1] = fname
  end

  local items = {}
  local function walk(node, depth)
    local dirs, fnodes = {}, {}
    for _, key in ipairs(node.order) do
      local c = node.children[key]
      if c.dir then dirs[#dirs + 1] = c else fnodes[#fnodes + 1] = c end
    end
    table.sort(dirs, function(a, b) return a.name < b.name end)
    table.sort(fnodes, function(a, b) return a.name < b.name end)
    for _, d in ipairs(dirs) do
      items[#items + 1] = { dir = true, depth = depth, name = d.name, text = d.name }
      walk(d, depth + 1)
    end
    for _, fl in ipairs(fnodes) do
      items[#items + 1] = { dir = false, depth = depth, name = fl.name, file_idx = fl.file_idx, path = fl.path, text = fl.path }
    end
  end
  walk(root, 0)
  return items
end

local function format_item(item)
  local indent = string.rep("  ", item.depth or 0)
  if item.dir then
    return { { indent, "Normal" }, { " " .. item.name, "Directory" } }
  end
  return { { indent, "Normal" }, { " " .. item.name, "SnacksPickerFile" } }
end

--- Open the changed-files tree for a PR.
--- @param repo string       "owner/repo"
--- @param n number          PR number
--- @param diff_text string  Raw unified diff (as from `gh pr diff`)
function M.open(repo, n, diff_text)
  if not (Snacks and Snacks.picker) then
    return vim.notify("DevOps: Snacks.picker not available", vim.log.levels.ERROR)
  end

  local files = {}
  for i, f in ipairs(diff_viewer.parse_files(diff_text)) do
    files[#files + 1] = { path = f.path, file_idx = i }
  end
  if #files == 0 then
    return vim.notify("DevOps: no changed files in #" .. n, vim.log.levels.INFO)
  end

  Snacks.picker.pick({
    source = "devops_pr_files",
    title = "PR #" .. n .. " · " .. #files .. " files",
    items = build_tree_items(files),
    format = format_item,
    -- Tree only, no diff preview (the diff lives in the normal viewer).
    layout = {
      preview = false,
      layout = {
        backdrop = false,
        width = 0.32,
        min_width = 42,
        height = 0.85,
        border = "rounded",
        box = "vertical",
        title = "{title}",
        title_pos = "center",
        { win = "input", height = 1, border = "bottom" },
        { win = "list", border = "none" },
      },
    },
    confirm = function(picker, item)
      if not item or item.dir then return end
      picker:close()
      diff_viewer.open(diff_text, "Diff #" .. n, {
        pr = { repo = repo, number = n },
        focus_file = item.file_idx,
      })
    end,
  })
end

return M
