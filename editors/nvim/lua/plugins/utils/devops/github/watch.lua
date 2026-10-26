---------------------------------------------------------------------------
-- Background GitHub watch: polls open review requests + the notification
-- count, notifies on new review requests and feeds the sidebar badges.
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")
local gh = require("plugins.utils.devops.github.api")

local M = {}

M.state = {
  requests = nil,  -- latest open review requests { id, title, url } (nil until polled)
  seen = {},       -- ids present when you last looked at Reviews
  notif = 0,
}

local timer
local on_change

local function id_of(pr)
  local repo = pr.repository and (pr.repository.nameWithOwner or pr.repository.name) or "?"
  return repo .. "#" .. tostring(pr.number)
end

-- Requests in `cur` that weren't in `prev` (a list of ids).
function M.new_requests(prev, cur)
  local had, out = {}, {}
  for _, id in ipairs(prev or {}) do had[id] = true end
  for _, r in ipairs(cur or {}) do if not had[r.id] then out[#out + 1] = r end end
  return out
end

-- Review requests you haven't looked at yet (since the last Reviews visit).
function M.unseen()
  local n = 0
  for _, r in ipairs(M.state.requests or {}) do if not M.state.seen[r.id] then n = n + 1 end end
  return n
end

function M.total() return M.state.requests and #M.state.requests or 0 end

-- Looking at the Reviews section clears the "new" mark.
function M.mark_seen()
  M.state.seen = {}
  for _, r in ipairs(M.state.requests or {}) do M.state.seen[r.id] = true end
  if on_change then on_change() end
end

function M.apply(list)
  local cur = {}
  for _, pr in ipairs(list or {}) do
    cur[#cur + 1] = { id = id_of(pr), title = pr.title or "", url = pr.url }
  end
  local first = M.state.requests == nil
  local prev = {}
  for _, r in ipairs(M.state.requests or {}) do prev[#prev + 1] = r.id end
  M.state.requests = cur
  if first then return {} end
  return M.new_requests(prev, cur)
end

function M.poll()
  if not gh.available() then return end
  gh.review_requests(function(ok, list)
    if not ok then return end
    for _, r in ipairs(M.apply(list)) do
      vim.notify("👀 Review requested: " .. r.id .. "  " .. r.title, vim.log.levels.INFO, { title = "DevOps" })
    end
    if on_change then on_change() end
  end)
  gh.notifications_count(function(count)
    M.state.notif = count
    if on_change then on_change() end
  end)
end

-- Start polling (idempotent). `cb` is called whenever counts change.
function M.start(cb)
  on_change = cb
  local every = tonumber(config.options.github.poll_interval) or 0
  M.poll()
  if every <= 0 or timer then return end
  timer = vim.uv.new_timer()
  timer:start(every * 1000, every * 1000, vim.schedule_wrap(M.poll))
end

function M.stop()
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  on_change = nil
end

return M
