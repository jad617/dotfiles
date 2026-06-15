---------------------------------------------------------------------------
-- Custom workspace manager (no external plugin)
--
-- Storage: ~/.local/share/nvim/workspaces  (compatible with workspaces.nvim)
-- Format per line: name path timestamp
--
-- On VimEnter: auto-add the current git repo (idempotent)
-- <c-l>: open Snacks picker — Path list left, Preview right
--        <c-d> inside the picker removes the highlighted workspace
-- :WorkspaceAdd [name]    add the current folder's root dir (optional name)
-- :WorkspaceAddDir [dir]  add an arbitrary directory (prompts, defaults to cwd)
-- :WorkspaceRemove name   manually remove a workspace by name
---------------------------------------------------------------------------

local DATA_FILE = vim.fn.stdpath("data") .. "/workspaces"

local function set_workspace_hl() vim.api.nvim_set_hl(0, "WorkspacePath", { fg = "#99bc80" }) end
set_workspace_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_workspace_hl })

---------------------------------------------------------------------------
-- Storage helpers
---------------------------------------------------------------------------
local function load_workspaces()
  local items = {}
  local f = io.open(DATA_FILE, "r")
  if not f then return items end
  for line in f:lines() do
    local name, path = line:match("^(%S+)%s+(%S+)")
    if name and path and vim.fn.isdirectory(path) == 1 then items[#items + 1] = { name = name, path = path } end
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
-- Add / remove core (shared by auto-add, commands and picker)
---------------------------------------------------------------------------
local function normalize_path(path)
  path = vim.fn.fnamemodify(path, ":p") -- expand to absolute
  if path:sub(-1) ~= "/" then path = path .. "/" end
  return path
end

-- Returns ok(boolean), message(string)
local function add_workspace(path, name)
  if not path or path == "" then return false, "No path given" end
  path = normalize_path(path)
  if vim.fn.isdirectory(path) == 0 then return false, "Not a directory: " .. path end
  if not name or name == "" then name = path:gsub("/$", ""):match("([^/]+)$") end

  local workspaces = load_workspaces()
  for _, ws in ipairs(workspaces) do
    if ws.path == path then return false, "Already a workspace: " .. ws.name end
    if ws.name == name then return false, "Workspace name in use: " .. name end
  end

  workspaces[#workspaces + 1] = { name = name, path = path }
  save_workspaces(workspaces)
  return true, ("Added workspace: %s → %s"):format(name, path)
end

-- Returns ok(boolean), message(string)
local function remove_workspace(key)
  if not key or key == "" then return false, "No workspace given" end
  local norm = normalize_path(key)
  local workspaces = load_workspaces()
  for i, ws in ipairs(workspaces) do
    if ws.name == key or ws.path == norm then
      table.remove(workspaces, i)
      save_workspaces(workspaces)
      return true, "Removed workspace: " .. ws.name
    end
  end
  return false, "No workspace matching: " .. key
end

---------------------------------------------------------------------------
-- Git repo detection
---------------------------------------------------------------------------
local function get_git_repo_name_and_root()
  local function trim(s) return (s:gsub("%s+$", "")) end
  local remote = trim(vim.fn.system("git remote get-url origin 2>/dev/null"))
  local root = trim(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"))
  if root == "" then return nil, nil end

  local name
  if remote ~= "" then
    name = remote:match("[:/](.-)%.git$")
    name = name and name:match("([^/]+)$") or nil
  end
  if not name or name == "" then name = root:match("([^/]+)$") end
  return name, root
end

---------------------------------------------------------------------------
-- Auto-add current git repo on startup (idempotent)
---------------------------------------------------------------------------
local function auto_add_workspace()
  local name, root = get_git_repo_name_and_root()
  if not name or not root then return end

  local ok, msg = add_workspace(root, name)
  if ok then vim.notify(msg, vim.log.levels.INFO) end -- stay silent when it already exists
end

local aug = vim.api.nvim_create_augroup("WorkspaceAutoAdd", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  group = aug,
  desc = "Auto-add current git repo as workspace",
  callback = function() vim.schedule(auto_add_workspace) end,
})

---------------------------------------------------------------------------
-- Snacks picker — input top, Path (name+path) left, Preview right
---------------------------------------------------------------------------
local function open_workspace_picker()
  local workspaces = load_workspaces()
  if #workspaces == 0 then
    vim.notify("No workspaces found", vim.log.levels.WARN)
    return
  end

  -- Compute dynamic column widths
  local max_name_w = 0
  local max_path_w = 0
  for _, ws in ipairs(workspaces) do
    local nw = vim.fn.strdisplaywidth(ws.name)
    local pw = vim.fn.strdisplaywidth(vim.fn.fnamemodify(ws.path, ":~"))
    if nw > max_name_w then max_name_w = nw end
    if pw > max_path_w then max_path_w = pw end
  end
  -- Available width in the Path panel (~75% of 80% picker, minus borders/separator)
  local available_w = math.floor(vim.o.columns * 0.8 * 0.75) - 6
  -- If everything fits, give the name column a little extra breathing room
  local name_col_w = max_name_w
  if max_name_w + max_path_w <= available_w then name_col_w = max_name_w + 15 end

  Snacks.picker({
    title = "Select",
    on_show = function() vim.cmd("startinsert") end,
    finder = function()
      local items = {}
      for _, ws in ipairs(workspaces) do
        items[#items + 1] = {
          text = ws.name,
          name = ws.name,
          path = ws.path,
          file = ws.path,
        }
      end
      return items
    end,
    format = function(item)
      local pad = name_col_w - vim.fn.strdisplaywidth(item.name)
      return {
        { item.name .. string.rep(" ", pad + 2), "SnacksPickerLabel" },
        { "│  ", "SnacksPickerDelim" },
        { vim.fn.fnamemodify(item.path, ":~"), "WorkspacePath" },
      }
    end,
    preview = "directory",
    actions = {
      delete_workspace = function(picker, item)
        if not item then return end
        local ok, msg = remove_workspace(item.path)
        vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN)
        if not ok then return end
        -- Drop it from the in-memory list backing the finder, then refresh
        for i, ws in ipairs(workspaces) do
          if ws.path == item.path then
            table.remove(workspaces, i)
            break
          end
        end
        if #workspaces == 0 then
          picker:close()
        else
          picker:find()
        end
      end,
    },
    win = {
      input = { keys = { ["<c-d>"] = { "delete_workspace", mode = { "n", "i" } } } },
      list = { keys = { ["<c-d>"] = "delete_workspace" } },
    },
    confirm = function(picker, item)
      picker:close()
      if not item then return end
      if vim.fn.isdirectory(item.path) == 0 then
        vim.notify("Workspace path missing: " .. item.path, vim.log.levels.ERROR)
        return
      end
      vim.fn.chdir(item.path)
      -- Open neo-tree once the user picks and opens a file from this project
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = vim.api.nvim_create_augroup("WorkspaceNeoTree", { clear = true }),
        once = true,
        callback = function()
          vim.schedule(function()
            require("neo-tree.command").execute({ action = "show", dir = item.path })
          end)
        end,
      })
      Snacks.picker.files({ hidden = true, cwd = item.path })
    end,
    layout = {
      layout = {
        box = "vertical",
        backdrop = false,
        width = 0.8,
        height = 0.9,
        border = "none",
        { win = "input", height = 1, border = true, title = " Select ", title_pos = "center" },
        {
          box = "horizontal",
          { win = "list", title = " Path ", title_pos = "center", border = true },
          { win = "preview", title = " Preview ", title_pos = "center", width = 0.25, border = true },
        },
      },
    },
  })
end

vim.api.nvim_create_user_command("SnacksWorkspaces", open_workspace_picker, {})
vim.keymap.set("n", "<c-l>", "<cmd>SnacksWorkspaces<cr>", { desc = "Workspaces (Snacks)" })

-- Add the current folder's root dir: ":WorkspaceAdd [name]"
-- Uses the git repo root when available, otherwise the current working dir.
vim.api.nvim_create_user_command("WorkspaceAdd", function(opts)
  local name, root = get_git_repo_name_and_root()
  root = root or vim.fn.getcwd()
  if opts.args ~= "" then name = opts.args end -- explicit name overrides the derived one
  local ok, msg = add_workspace(root, name)
  vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN)
end, { nargs = "?", desc = "Add the current folder's root as a workspace" })

-- Add an arbitrary directory: ":WorkspaceAddDir [dir]" (prompts, defaults to cwd)
vim.api.nvim_create_user_command("WorkspaceAddDir", function(opts)
  local function do_add(path)
    if not path or path == "" then return end
    local ok, msg = add_workspace(vim.fn.expand(path))
    vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN)
  end
  if opts.args ~= "" then
    do_add(opts.args)
  else
    vim.ui.input({ prompt = "Workspace directory: ", default = vim.fn.getcwd() .. "/", completion = "dir" }, do_add)
  end
end, { nargs = "?", complete = "dir", desc = "Add a directory as a workspace" })

-- Manually remove a workspace by name: ":WorkspaceRemove <name>" (tab-completes names)
vim.api.nvim_create_user_command("WorkspaceRemove", function(opts)
  local ok, msg = remove_workspace(opts.args)
  vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN)
end, {
  nargs = 1,
  desc = "Remove a workspace by name",
  complete = function(arg_lead)
    local names = {}
    for _, ws in ipairs(load_workspaces()) do
      if ws.name:find(arg_lead, 1, true) then names[#names + 1] = ws.name end
    end
    return names
  end,
})

return {}
