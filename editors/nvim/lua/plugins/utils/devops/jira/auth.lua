---------------------------------------------------------------------------
-- Jira credential storage + interactive setup (:JiraAuth)
--
-- Credentials are written to  $XDG_CONFIG_HOME/devops/credentials.json
-- (defaults to ~/.config/devops/credentials.json), with the directory at
-- mode 0700 and the file at 0600 so only you can read it.
--
-- Environment variables (JIRA_URL/JIRA_EMAIL/JIRA_API_TOKEN) still take
-- precedence over the stored file — see jira/client.lua.
---------------------------------------------------------------------------

local M = {}

function M.dir()
  local base = os.getenv("XDG_CONFIG_HOME")
  if not base or base == "" then base = vim.fn.expand("~/.config") end
  return base .. "/devops"
end

function M.file() return M.dir() .. "/credentials.json" end

-- Returns { url, email, token } or nil if nothing stored / unreadable.
function M.load()
  local f = io.open(M.file(), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  return data
end

-- Persist creds with locked-down permissions. Returns ok, err.
function M.save(creds)
  local dir = M.dir()
  vim.fn.mkdir(dir, "p", tonumber("700", 8))
  pcall(vim.uv.fs_chmod, dir, tonumber("700", 8))

  local f = io.open(M.file(), "w")
  if not f then return false, "cannot write " .. M.file() end
  f:write(vim.json.encode(creds))
  f:close()
  pcall(vim.uv.fs_chmod, M.file(), tonumber("600", 8))
  return true
end

-- Remove stored credentials. Returns ok.
function M.clear()
  if vim.uv.fs_stat(M.file()) then
    return pcall(vim.uv.fs_unlink, M.file())
  end
  return true
end

-- Interactive prompt → save. on_done(creds) runs after a successful save.
-- URL/email use vim.ui.input; the token uses inputsecret() so it is masked.
function M.setup_interactive(on_done)
  local existing = M.load() or {}

  vim.ui.input({
    prompt = "Jira URL: ",
    default = existing.url or "https://yourorg.atlassian.net",
  }, function(url)
    if not url or url == "" then
      return vim.notify("JiraAuth cancelled", vim.log.levels.WARN)
    end
    url = url:gsub("/+$", "")

    vim.ui.input({ prompt = "Jira email: ", default = existing.email or "" }, function(email)
      if not email or email == "" then
        return vim.notify("JiraAuth cancelled", vim.log.levels.WARN)
      end

      -- Run the masked token prompt after the ui.input UI has closed.
      vim.schedule(function()
        local hint = existing.token and " (leave blank to keep current)" or ""
        local token = vim.fn.inputsecret("Jira API token" .. hint .. ": ")
        if token == "" then token = existing.token end
        if not token or token == "" then
          return vim.notify("JiraAuth cancelled (no token)", vim.log.levels.WARN)
        end

        local creds = { url = url, email = email, token = token }
        local ok, err = M.save(creds)
        if not ok then
          return vim.notify("JiraAuth: " .. (err or "save failed"), vim.log.levels.ERROR)
        end
        if on_done then on_done(creds) end
      end)
    end)
  end)
end

return M
