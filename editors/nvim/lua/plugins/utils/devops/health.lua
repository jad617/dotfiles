---------------------------------------------------------------------------
-- DevOps health report (:DevOpsHealth) — env vars, gh, curl, Jira auth.
-- Shown in a small float so it works regardless of checkhealth module paths.
---------------------------------------------------------------------------

local client = require("plugins.utils.devops.jira.client")
local gh = require("plugins.utils.devops.github.api")

local M = {}

local function show(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  width = math.min(math.max(width + 2, 30), vim.o.columns - 4)
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal", border = "rounded", title = " DevOps health ", title_pos = "center",
  })
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = buf, nowait = true })
  end
  return buf, win
end

function M.run()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end

  -- Jira credentials (env or stored file)
  local auth = require("plugins.utils.devops.jira.auth")
  local miss = client.missing()
  if #miss == 0 then
    add("✓ Jira credentials present")
    add("   URL: " .. client.base_url())
    if auth.load() then add("   stored: " .. auth.file()) end
  else
    add("✗ Jira credentials missing: " .. table.concat(miss, ", "))
    add("   Run :JiraAuth to set them up (saved to " .. auth.file() .. "),")
    add("   or export JIRA_URL / JIRA_EMAIL / JIRA_API_TOKEN.")
  end

  -- Remembered Jira project / board (a missing board → empty Sprint Board)
  local prefs = require("plugins.utils.devops.store").load() or {}
  if prefs.project_key then
    add("✓ Jira project: " .. prefs.project_key
      .. (prefs.board_id and ("  ·  board " .. prefs.board_id) or "  ⚠ no board (Sprint Board needs 'b')"))
  else
    add("· No Jira project remembered yet — pick one with 'p' in the dashboard")
  end

  -- gh
  add(gh.available() and "✓ gh CLI found" or "✗ gh CLI not found (GitHub sections disabled)")
  -- curl
  add(vim.fn.executable("curl") == 1 and "✓ curl found" or "✗ curl not found")

  add("· Jira auth: checking…")
  local buf = show(lines)

  if #miss == 0 then
    client.myself(function(ok, data, err)
      if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
      lines[#lines] = ok
        and ("✓ Jira auth OK — " .. (data and data.displayName or "?"))
        or ("✗ Jira auth failed — " .. (err or "?"))
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
    end)
  else
    lines[#lines] = "· Jira auth: skipped (env missing)"
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
end

return M
