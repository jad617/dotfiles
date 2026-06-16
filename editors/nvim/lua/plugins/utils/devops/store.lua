---------------------------------------------------------------------------
-- DevOps preferences (non-secret) — remembers the selected project/board.
-- Stored next to the credentials file: $XDG_CONFIG_HOME/devops/state.json
---------------------------------------------------------------------------

local auth = require("plugins.utils.devops.jira.auth")

local M = {}

function M.file() return auth.dir() .. "/state.json" end

function M.load()
  local f = io.open(M.file(), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return nil end
  return data
end

function M.save(tbl)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.file(), "w")
  if not f then return false end
  f:write(vim.json.encode(tbl))
  f:close()
  return true
end

return M
