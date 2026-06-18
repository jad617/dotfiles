---------------------------------------------------------------------------
-- Multiline input — scratch float for composing comments/descriptions.
-- <C-s> submits (normal or insert), q/Esc cancels (normal only).
-- @    inserts a @mention in normal mode (when on_mention is provided).
---------------------------------------------------------------------------

local M = {}

--- Insert text at cursor position in the given buffer/window.
local function insert_at_cursor(buf, win, text)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { before .. text .. after })
  vim.api.nvim_win_set_cursor(win, { row, col + #text })
end

--- Open a scratch float for multiline text input.
--- @param title string  Window title shown in the border
--- @param initial string|nil  Pre-filled text (newline-separated)
--- @param on_submit fun(text: string)  Called with the buffer text on submit
--- @param opts table|nil  Optional: { on_mention = fun(insert_fn) }
function M.open(title, initial, on_submit, opts)
  opts = opts or {}
  local prev_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial or "", "\n", { plain = true }))

  local hint = "<C-s> submit, q cancel"
  if opts.on_mention then hint = hint .. ", @ mention" end

  local w = math.floor(vim.o.columns * 0.6)
  local h = math.floor(vim.o.lines * 0.4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " (" .. hint .. ") ",
    title_pos = "center",
  })

  -- Place cursor at the end of the last line and enter insert mode.
  local line_count = vim.api.nvim_buf_line_count(buf)
  local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""
  vim.api.nvim_win_set_cursor(win, { line_count, #last_line })
  vim.cmd("startinsert!")

  local closed = false
  local function do_close()
    if closed then return end
    closed = true
    vim.cmd("stopinsert")
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  local function submit()
    if closed then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    vim.cmd("stopinsert")
    do_close()
    on_submit(text)
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "Submit" })
  vim.keymap.set("n", "q", do_close, { buffer = buf, desc = "Cancel" })
  vim.keymap.set("n", "<C-d>", do_close, { buffer = buf, desc = "Cancel" })
  vim.keymap.set("n", "<Esc>", do_close, { buffer = buf, desc = "Cancel" })

  -- Mention support: @ in normal mode triggers the user picker.
  if opts.on_mention then
    vim.keymap.set("n", "@", function()
      opts.on_mention(function(text)
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
          insert_at_cursor(buf, win, text)
        end
      end)
    end, { buffer = buf, nowait = true, desc = "Insert @mention" })
  end
end

return M
