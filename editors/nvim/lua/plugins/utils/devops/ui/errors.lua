---------------------------------------------------------------------------
-- Action errors in a visible float (a toast is easy to miss, and gh/Jira
-- errors are often multi-line). Errors arriving while it's open are appended.
-- Still logged via vim.notify so they stay in :messages / notification history.
---------------------------------------------------------------------------
local M = {}

local win, buf

local function close()
  if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
  win = nil
end

local function message_lines(msg)
  msg = tostring(msg or "unknown error"):gsub("^DevOps:%s*", ""):gsub("%s+$", "")
  local out = {}
  for _, l in ipairs(vim.split(msg, "\n", { plain = true })) do
    out[#out + 1] = " " .. l:gsub("\r", "")
  end
  return out
end

function M.show(msg)
  vim.notify(tostring(msg), vim.log.levels.ERROR)
  if #vim.api.nvim_list_uis() == 0 then return end -- headless: notify only

  local lines = message_lines(msg)
  if win and vim.api.nvim_win_is_valid(win) and buf and vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.list_extend({ "" }, lines))
    vim.bo[buf].modifiable = false
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  else
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    for _, k in ipairs({ "q", "<Esc>", "<CR>" }) do
      vim.keymap.set("n", k, close, { buffer = buf, nowait = true, desc = "Close" })
    end
  end

  local width = 30
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l) + 1) end
  width = math.min(width, math.floor(vim.o.columns * 0.7))
  local rows = 0
  for _, l in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  local height = math.min(rows, math.floor(vim.o.lines * 0.5))
  local cfg = {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " ✗ DevOps error ",
    title_pos = "center",
    footer = " q / Esc / ↵ close ",
    footer_pos = "center",
    zindex = 250,
  }
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_config(win, cfg)
  else
    win = vim.api.nvim_open_win(buf, true, cfg)
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:DiagnosticError,FloatTitle:DiagnosticError,FloatFooter:Comment"
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = buf,
      once = true,
      callback = function() vim.schedule(close) end,
    })
  end
end

return M
