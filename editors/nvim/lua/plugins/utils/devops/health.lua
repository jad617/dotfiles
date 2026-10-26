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
  for _, k in ipairs({ "q", "<C-d>", "<Esc>" }) do
    vim.keymap.set("n", k, function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end, { buffer = buf, nowait = true })
  end
  return buf, win
end

-- Scopes listed by `gh auth status` ("- Token scopes: 'repo', ..."), or nil
-- when the token doesn't report any (fine-grained tokens, GitHub App).
function M.parse_gh_scopes(text)
  local line = (text or ""):match("Token scopes:%s*([^\n]*)")
  if not line then return nil end
  local out = {}
  for sc in line:gmatch("'([^']+)'") do out[sc] = true end
  return out
end

-- What the plugin needs from a classic token; a broader scope also satisfies.
local NEEDED = {
  { "repo", { "repo" }, "PRs, diffs, reviews" },
  { "read:org", { "read:org", "write:org", "admin:org" }, "team review requests" },
  { "notifications", { "notifications", "repo" }, "notification badge" },
}

-- Missing scopes as { "read:org (team review requests)", ... }.
function M.missing_gh_scopes(scopes)
  local miss = {}
  for _, n in ipairs(NEEDED) do
    local any = false
    for _, s in ipairs(n[2]) do any = any or scopes[s] == true end
    if not any then miss[#miss + 1] = n[1] .. " (" .. n[3] .. ")" end
  end
  return miss
end

function M.run()
  local lines = {}
  local buf, win
  local function add(s) lines[#lines + 1] = s; return #lines end
  local function set(i, s)
    lines[i] = s
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      if win and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_set_height, win, #lines) end
    end
  end

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
  local jira_line = add(#miss == 0 and "· Jira auth: checking…" or "· Jira auth: skipped (credentials missing)")

  -- Remembered Jira project / board (a missing board → empty Sprint Board)
  local prefs = require("plugins.utils.devops.store").load() or {}
  local proj_line
  if prefs.project_key then
    proj_line = add("· Jira project " .. prefs.project_key .. ": checking…")
  else
    add("· No Jira project remembered yet — pick one with 'p' in the dashboard")
  end

  -- gh + token scopes
  local gh_line
  if gh.available() then
    gh_line = add("· gh: checking login…")
  else
    add("✗ gh CLI not found (GitHub sections disabled)")
  end
  add(vim.fn.executable("curl") == 1 and "✓ curl found" or "✗ curl not found")
  add(vim.fn.executable("git") == 1 and "✓ git found" or "✗ git not found (branch from issue disabled)")

  buf, win = show(lines)

  if #miss == 0 then
    client.myself(function(ok, data, err)
      set(jira_line, ok and ("✓ Jira auth OK — " .. (data and data.displayName or "?"))
        or ("✗ Jira auth failed — " .. (err or "?")))
    end)
    if proj_line then
      client.get("/rest/api/3/project/" .. prefs.project_key, function(ok, _, err)
        set(proj_line, ok
          and ("✓ Jira project " .. prefs.project_key
            .. (prefs.board_id and ("  ·  board " .. prefs.board_id) or "  ⚠ no board (Sprint Board needs 'b')"))
          or ("✗ Jira project " .. prefs.project_key .. " not accessible — " .. (err or "?")))
      end)
    end
  elseif proj_line then
    set(proj_line, "· Jira project " .. prefs.project_key .. " (not checked)")
  end

  if gh_line then
    vim.system({ "gh", "auth", "status", "--hostname", "github.com" }, { text = true }, function(res)
      vim.schedule(function()
        local out = (res.stdout or "") .. (res.stderr or "")
        if res.code ~= 0 then
          return set(gh_line, "✗ gh not logged in — run `gh auth login`")
        end
        local who = out:match("account (%S+)") or "?"
        set(gh_line, "✓ gh logged in as " .. who)
        local scopes = M.parse_gh_scopes(out)
        local text
        if not scopes then
          text = "   token scopes not reported (fine-grained token) — not checked"
        else
          local m = M.missing_gh_scopes(scopes)
          text = #m == 0 and "✓ gh token scopes OK (repo, read:org, notifications)"
            or ("✗ gh token missing: " .. table.concat(m, ", ")
              .. " — `gh auth refresh -s " .. table.concat(vim.tbl_map(function(x) return x:match("^%S+") end, m), ",") .. "`")
        end
        table.insert(lines, gh_line + 1, text)
        set(gh_line + 1, text)
      end)
    end)
  end
end

return M
