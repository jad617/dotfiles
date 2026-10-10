-- Global
local M = {}

function M.FileNotTooBig()
  local fsize = vim.fn.getfsize(vim.fn.expand("%:p:f"))
  return fsize <= 1000000 -- Adjust the threshold as needed
  -- return fsize <= 0.1 -- Adjust the threshold as needed
end

-- Focus the adjacent WezTerm pane. A zoomed pane (Ctrl-a z) is enforced by
-- WezTerm itself: with unzoom_on_switch_pane = false the switch is a no-op.
function M.wezterm_pane(dir)
  local pane_id = vim.env.WEZTERM_PANE
  if not pane_id or pane_id == "" then return end
  vim.system({ "wezterm", "cli", "activate-pane-direction", "--pane-id", pane_id, dir }, { detach = true })
end

-- Root of the project `file` belongs to, or nil. Priority: Terraform root
-- (topmost dir in the unbroken chain of dirs holding *.tf) → Helm chart root
-- (topmost Chart.yaml, so subcharts resolve to the parent chart) → git root.
-- The search stays inside the git repo (or below $HOME when there's no repo).
function M.project_root(file)
  local start = vim.fs.dirname(file)
  if vim.fn.isdirectory(start) == 0 then return nil end
  local git = vim.fs.root(start, ".git")
  local home = vim.uv.os_homedir()

  local dirs, d = {}, start
  while d do
    if not git and (d == home or d == "/") then break end
    dirs[#dirs + 1] = d
    if d == git then break end
    local parent = vim.fs.dirname(d)
    if parent == d then break end
    d = parent
  end

  local function has_tf(dir) return vim.fn.glob(dir .. "/*.tf", true, true)[1] ~= nil end
  for i, dir in ipairs(dirs) do
    if has_tf(dir) then
      while dirs[i + 1] and has_tf(dirs[i + 1]) do i = i + 1 end
      return dirs[i]
    end
  end

  local chart
  for _, dir in ipairs(dirs) do
    if vim.uv.fs_stat(dir .. "/Chart.yaml") then chart = dir end
  end
  return chart or git
end

return M
