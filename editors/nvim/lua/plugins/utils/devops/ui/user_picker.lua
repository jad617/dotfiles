---------------------------------------------------------------------------
-- Live-search user picker — a two-pane float (search input + results list)
-- that queries Jira as you type with debounced API calls.
--
-- Tab / S-Tab / C-j / C-k  navigate results
-- Enter                     selects
-- Esc / q                   cancels
---------------------------------------------------------------------------

local M = {}
local api = require("plugins.utils.devops.jira.api")
local ns = vim.api.nvim_create_namespace("devops_user_picker")

--- Open the live-search user picker.
--- @param on_select fun(choice: {name:string, id:string})  called with the picked user
--- @param opts table|nil  { title = string }
function M.open(on_select, opts)
  opts = opts or {}
  local title = opts.title or "Search User"
  local prev_win = vim.api.nvim_get_current_win()

  -- Buffers ------------------------------------------------------------------
  local input_buf = vim.api.nvim_create_buf(false, true)
  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].bufhidden = "wipe"
  vim.bo[list_buf].bufhidden = "wipe"
  vim.bo[list_buf].modifiable = false

  -- Layout -------------------------------------------------------------------
  local w = math.min(math.floor(vim.o.columns * 0.4), 60)
  local list_h = 10
  local row = math.floor((vim.o.lines - list_h - 4) / 2)
  local col = math.floor((vim.o.columns - w) / 2)

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    width = w,
    height = 1,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
    zindex = 300,
  })

  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor",
    width = w,
    height = list_h,
    row = row + 3,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Tab ↑↓  ⏎ Select  Esc Cancel ",
    title_pos = "center",
    zindex = 300,
  })

  -- State --------------------------------------------------------------------
  local users = {}
  local sel = 1
  local timer = vim.uv.new_timer()
  local closed = false

  -- Render results list with selection highlight.
  local function render()
    vim.bo[list_buf].modifiable = true
    local lines = {}
    for i, u in ipairs(users) do
      lines[i] = (i == sel and " ▸ " or "   ") .. u.name
    end
    if #lines == 0 then lines = { "   type to search…" } end
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
    vim.bo[list_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(list_buf, ns, 0, -1)
    if #users > 0 and sel <= #users then
      vim.api.nvim_buf_add_highlight(list_buf, ns, "Visual", sel - 1, 0, -1)
    end
  end

  local function do_close()
    if closed then return end
    closed = true
    timer:stop()
    if vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    if vim.api.nvim_win_is_valid(list_win) then vim.api.nvim_win_close(list_win, true) end
    if prev_win and vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
  end

  -- Debounced search (300 ms).
  local function search(query)
    timer:stop()
    timer:start(300, 0, vim.schedule_wrap(function()
      if closed then return end
      api.search_users(query, function(ok, data)
        if not ok or closed then return end
        users = {}
        for _, u in ipairs(data) do
          if u.accountId and u.accountType ~= "app" then
            users[#users + 1] = { name = u.displayName or u.accountId, id = u.accountId }
          end
        end
        sel = math.min(sel, math.max(1, #users))
        render()
      end)
    end))
  end

  -- React to typing.
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = input_buf,
    callback = function()
      if closed then return end
      local q = (vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or "")
      search(q)
    end,
  })

  -- Keymaps ------------------------------------------------------------------
  local function km(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = input_buf, nowait = true, desc = desc })
  end

  km({ "i", "n" }, "<Tab>", function()
    if #users > 0 then sel = (sel % #users) + 1; render() end
  end, "Next result")

  km({ "i", "n" }, "<S-Tab>", function()
    if #users > 0 then sel = ((sel - 2) % #users) + 1; render() end
  end, "Prev result")

  km({ "i", "n" }, "<C-j>", function()
    if #users > 0 then sel = (sel % #users) + 1; render() end
  end, "Next result")

  km({ "i", "n" }, "<C-k>", function()
    if #users > 0 then sel = ((sel - 2) % #users) + 1; render() end
  end, "Prev result")

  km({ "i", "n" }, "<CR>", function()
    if #users > 0 and users[sel] then
      local choice = users[sel]
      do_close()
      on_select(choice)
    end
  end, "Select user")

  km({ "i", "n" }, "<Esc>", do_close, "Cancel")
  km("n", "q", do_close, "Cancel")

  -- Start in insert mode and show initial placeholder.
  vim.cmd("startinsert")
  render()
end

return M
