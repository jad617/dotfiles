---------------------------------------------------------------------------
-- Shift+Arrow navigation for DevOps windows. Most of them are floats, which
-- smart-splits can't traverse, so each view declares its own pane order:
-- Shift+Left/Right step through `h` panes, Shift+Up/Down through `v` panes,
-- and past the edges focus moves to the adjacent WezTerm pane. WezTerm
-- itself blocks that while the pane is zoomed (unzoom_on_switch_pane = false).
---------------------------------------------------------------------------

local M = {}

local function step(dir, list_fn)
  if not list_fn then return false end
  local order = vim.tbl_filter(function(w)
    return w and vim.api.nvim_win_is_valid(w)
  end, list_fn())
  local cur = vim.api.nvim_get_current_win()
  local delta = (dir == "Left" or dir == "Up") and -1 or 1
  for i, w in ipairs(order) do
    if w == cur then
      local target = order[i + delta]
      if target then
        vim.api.nvim_set_current_win(target)
        return true
      end
      return false
    end
  end
  return false
end

--- Move one pane in `dir` ("Left"|"Right"|"Up"|"Down").
--- @param panes table|nil { h = fun(): integer[], v = fun(): integer[] }
function M.move(dir, panes)
  panes = panes or {}
  local list_fn = (dir == "Left" or dir == "Right") and panes.h or panes.v
  if step(dir, list_fn) then return end
  pcall(require("config.global_functions").wezterm_pane, dir)
end

--- Map <S-Left/Right/Up/Down> on `buf` (normal mode).
--- @param panes table|nil see M.move
function M.map(buf, panes)
  for _, dir in ipairs({ "Left", "Right", "Up", "Down" }) do
    vim.keymap.set("n", "<S-" .. dir .. ">", function() M.move(dir, panes) end, {
      buffer = buf, nowait = true, silent = true, desc = "Pane / WezTerm " .. dir:lower(),
    })
  end
end

return M
