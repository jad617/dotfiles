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

function M.bookmarks_file() return auth.dir() .. "/bookmarks.json" end

function M.load_bookmarks()
  local f = io.open(M.bookmarks_file(), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  -- Migrate old flat array format to per-section map
  if data[1] ~= nil then return {} end
  return data
end

function M.save_bookmarks(bookmarks)
  vim.fn.mkdir(auth.dir(), "p", tonumber("700", 8))
  local f = io.open(M.bookmarks_file(), "w")
  if not f then return false end
  f:write(vim.json.encode(bookmarks))
  f:close()
  return true
end

return M
