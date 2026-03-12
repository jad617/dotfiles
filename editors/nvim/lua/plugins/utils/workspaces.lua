---------------------------------------------------------------------------
-- Custom workspace manager (no external plugin)
--
-- Storage: ~/.local/share/nvim/workspaces  (compatible with workspaces.nvim)
-- Format per line: name path timestamp
--
-- On VimEnter: auto-add the current git repo (idempotent)
-- <c-l>: open Snacks picker — name on left, directory preview on right
---------------------------------------------------------------------------

local DATA_FILE = vim.fn.stdpath("data") .. "/workspaces"

---------------------------------------------------------------------------
-- Storage helpers
---------------------------------------------------------------------------
local function load_workspaces()
  local items = {}
  local f = io.open(DATA_FILE, "r")
  if not f then return items end
  for line in f:lines() do
    -- format: name path [timestamp]  (space-separated; path has no spaces)
    local name, path = line:match("^(%S+)%s+(%S+)")
    if name and path and vim.fn.isdirectory(path) == 1 then
      items[#items + 1] = { name = name, path = path }
    end
  end
  f:close()
  return items
end

local function save_workspaces(workspaces)
  vim.fn.mkdir(vim.fn.fnamemodify(DATA_FILE, ":h"), "p")
  local f = io.open(DATA_FILE, "w")
  if not f then return end
  local ts = os.date("!%Y-%m-%dT%H:%M:%S")
  for _, ws in ipairs(workspaces) do
    f:write(ws.name .. " " .. ws.path .. " " .. ts .. "\n")
  end
  f:close()
end

---------------------------------------------------------------------------
-- Git repo detection
---------------------------------------------------------------------------
local function get_git_repo_name_and_root()
  local function trim(s) return (s:gsub("%s+$", "")) end
  local remote = trim(vim.fn.system("git remote get-url origin 2>/dev/null"))
  local root   = trim(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"))
  if root == "" then return nil, nil end

  local name
  if remote ~= "" then
    name = remote:match("[:/](.-)%.git$")
    name = name and name:match("([^/]+)$") or nil
  end
  if not name or name == "" then
    name = root:match("([^/]+)$")
  end
  return name, root
end

---------------------------------------------------------------------------
-- Auto-add current git repo on startup (idempotent)
---------------------------------------------------------------------------
local function auto_add_workspace()
  local name, root = get_git_repo_name_and_root()
  if not name or not root then return end

  local workspaces = load_workspaces()
  for _, ws in ipairs(workspaces) do
    if ws.name == name or ws.path == root then return end
  end

  -- Ensure trailing slash for directory entries
  if root:sub(-1) ~= "/" then root = root .. "/" end
  workspaces[#workspaces + 1] = { name = name, path = root }
  save_workspaces(workspaces)
  vim.notify(("Added workspace: %s → %s"):format(name, root), vim.log.levels.INFO)
end

local aug = vim.api.nvim_create_augroup("WorkspaceAutoAdd", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  group    = aug,
  desc     = "Auto-add current git repo as workspace",
  callback = function() vim.schedule(auto_add_workspace) end,
})

---------------------------------------------------------------------------
-- Snacks picker — input on top, Project names left, Path right
-- (Snacks supports 3 window types: input / list / preview)
-- The preview window is repurposed to show the path of the selected item.
---------------------------------------------------------------------------
local function open_workspace_picker()
  local workspaces = load_workspaces()
  if #workspaces == 0 then
    vim.notify("No workspaces found", vim.log.levels.WARN)
    return
  end

  Snacks.picker({
    title   = "Select",
    finder  = function()
      local items = {}
      for _, ws in ipairs(workspaces) do
        items[#items + 1] = {
          text = ws.name,
          name = ws.name,
          path = ws.path,
        }
      end
      return items
    end,
    -- List shows only the project name
    format  = function(item)
      return { { item.name, "SnacksPickerLabel" } }
    end,
    -- Preview window shows the path of the highlighted item
    preview = function(ctx)
      ctx.preview:reset()
      ctx.preview:set_lines({ vim.fn.fnamemodify(ctx.item.path, ":~") })
    end,
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      if vim.fn.isdirectory(item.path) == 0 then
        vim.notify("Workspace path missing: " .. item.path, vim.log.levels.ERROR)
        return
      end
      vim.fn.chdir(item.path)
      Snacks.picker.files({ hidden = true, cwd = item.path })
    end,
    layout  = {
      layout = {
        box      = "vertical",
        backdrop = false,
        width    = 0.8,
        height   = 0.9,
        border   = "none",
        { win = "input", height = 1, border = true, title = " Select ", title_pos = "center" },
        {
          box = "horizontal",
          { win = "list",    title = " Project ", title_pos = "center", border = true },
          { win = "preview", title = " Path ",    title_pos = "center", width = 0.55, border = true },
        },
      },
    },
  })
end

vim.api.nvim_create_user_command("SnacksWorkspaces", open_workspace_picker, {})
vim.keymap.set("n", "<c-l>", "<cmd>SnacksWorkspaces<cr>", { desc = "Workspaces (Snacks)" })

return {}
