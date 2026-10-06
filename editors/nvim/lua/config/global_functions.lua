-- Global
local M = {}

function M.FileNotTooBig()
  local fsize = vim.fn.getfsize(vim.fn.expand("%:p:f"))
  return fsize <= 1000000 -- Adjust the threshold as needed
  -- return fsize <= 0.1 -- Adjust the threshold as needed
end

-- Focus the adjacent WezTerm pane, unless the current pane is zoomed
-- (Ctrl-a z) — matches smart-splits' disable_multiplexer_nav_when_zoomed and
-- WezTerm's unzoom_on_switch_pane = false, so a zoomed pane stays full screen.
function M.wezterm_pane(dir)
  local pane_id = vim.env.WEZTERM_PANE
  if not pane_id or pane_id == "" then return end
  local res = vim.system({ "wezterm", "cli", "list", "--format", "json" }, { text = true }):wait()
  local ok, panes = pcall(vim.json.decode, res.stdout or "")
  if res.code == 0 and ok and type(panes) == "table" then
    for _, p in ipairs(panes) do
      if tostring(p.pane_id) == pane_id and p.is_zoomed then return end
    end
  end
  vim.system({ "wezterm", "cli", "activate-pane-direction", "--pane-id", pane_id, dir }, { detach = true })
end

return M
