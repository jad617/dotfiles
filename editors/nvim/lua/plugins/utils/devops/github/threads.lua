---------------------------------------------------------------------------
-- Review-thread analysis (pure — unit tested in tests/run.lua).
---------------------------------------------------------------------------

local M = {}

--- Derive my comment status on a PR from its unresolved review threads.
--- GitHub threads are linear, so anyone commenting after my last comment in a
--- thread is replying to me.
--- @param threads table[]  reviewThreads.nodes ({ isResolved, comments = { nodes = { {author={login}} } } })
--- @param me string  current user login
--- @return string|nil status  "replied" | "awaiting_reply" | nil
--- @return table info  { reply_threads = n, repliers = string[] (sorted), awaiting_threads = n }
function M.comment_status(threads, me)
  local info = { reply_threads = 0, repliers = {}, awaiting_threads = 0 }
  if not (me and threads) then return nil, info end
  local seen = {}
  for _, thread in ipairs(threads) do
    local comments = not thread.isResolved and thread.comments and thread.comments.nodes
    if comments then
      local my_last
      for i, c in ipairs(comments) do
        if c.author and c.author.login == me then my_last = i end
      end
      if my_last == #comments then
        info.awaiting_threads = info.awaiting_threads + 1
      elseif my_last then
        info.reply_threads = info.reply_threads + 1
        for i = my_last + 1, #comments do
          local login = comments[i].author and comments[i].author.login
          if login and login ~= me and not seen[login] then
            seen[login] = true
            info.repliers[#info.repliers + 1] = login
          end
        end
      end
    end
  end
  table.sort(info.repliers)
  if info.reply_threads > 0 then return "replied", info end
  if info.awaiting_threads > 0 then return "awaiting_reply", info end
  return nil, info
end

--- Dashboard label for a "replied" status.
function M.reply_label(info)
  local who = #info.repliers > 0 and (" · " .. table.concat(info.repliers, ", ")) or ""
  if info.reply_threads > 1 then
    return "↩ " .. info.reply_threads .. " replies to your comments" .. who
  end
  return "↩ Reply to your comment" .. who
end

--- Effective review state per reviewer, the way GitHub computes it: a later
--- COMMENTED review (e.g. a reply in a thread) does not replace APPROVED /
--- CHANGES_REQUESTED; only a later verdict or a DISMISSED review does.
--- @param reviews table[]  { author = { login }, state, submittedAt }  (any order)
--- @return table<string, string>  login → "APPROVED" | "CHANGES_REQUESTED" | "COMMENTED" | ...
function M.review_verdicts(reviews)
  local sorted = {}
  for i, r in ipairs(reviews or {}) do sorted[#sorted + 1] = { r = r, i = i } end
  table.sort(sorted, function(a, b)
    local ta, tb = a.r.submittedAt or "", b.r.submittedAt or ""
    if ta ~= tb then return ta < tb end
    return a.i < b.i
  end)
  local out = {}
  for _, e in ipairs(sorted) do
    local login = e.r.author and e.r.author.login
    local st = e.r.state
    if login and st and st ~= "" and st ~= "PENDING" then
      local cur = out[login]
      if st == "DISMISSED" then
        out[login] = "COMMENTED"
      elseif st ~= "COMMENTED" or not (cur == "APPROVED" or cur == "CHANGES_REQUESTED") then
        out[login] = st
      end
    end
  end
  return out
end

-- One-line merge readiness for the PR Status block.
-- r = { decision = reviewDecision, verdicts = review_verdicts(...), author,
--       me, required = number|nil, code_owners = bool, owner_pending = {names} }
-- → text, level ("ok" | "warn" | "err")
function M.merge_readiness(r)
  local approvals, changes = 0, 0
  for login, st in pairs(r.verdicts or {}) do
    if login ~= r.author then
      if st == "APPROVED" then approvals = approvals + 1 end
      if st == "CHANGES_REQUESTED" then changes = changes + 1 end
    end
  end
  local parts, level = {}, "warn"
  local mine = r.me and r.verdicts and r.verdicts[r.me]
  if mine == "APPROVED" then
    parts[#parts + 1] = "✓ you approved"
  elseif mine == "CHANGES_REQUESTED" then
    parts[#parts + 1] = "✗ you requested changes"
  end
  local req = tonumber(r.required) or 0
  if req > 0 then
    parts[#parts + 1] = ("%d/%d approvals"):format(approvals, req)
  elseif approvals > 0 then
    parts[#parts + 1] = approvals .. " approval" .. (approvals == 1 and "" or "s")
  end
  if r.decision == "APPROVED" then
    level = "ok"
    table.insert(parts, 1, "approved")
  elseif r.decision == "CHANGES_REQUESTED" or changes > 0 then
    level = "err"
    table.insert(parts, 1, "changes requested")
  elseif r.decision == "REVIEW_REQUIRED" then
    if req > approvals then
      parts[#parts + 1] = "needs " .. (req - approvals) .. " more"
    end
    if r.owner_pending and #r.owner_pending > 0 then
      parts[#parts + 1] = "code owner: " .. table.concat(r.owner_pending, ", ")
    elseif r.code_owners and req <= approvals then
      parts[#parts + 1] = "code owner review needed"
    end
    table.insert(parts, 1, "review required")
  elseif #parts == 0 then
    return nil
  end
  return table.concat(parts, " · "), level
end

-- My latest APPROVED / CHANGES_REQUESTED review (thread replies are COMMENTED
-- reviews and don't count). → { state, commit = oid, at } | nil
function M.my_last_verdict(reviews, me)
  if not me then return nil end
  local best
  for _, r in ipairs(reviews or {}) do
    local login = r.author and r.author.login
    if login == me and (r.state == "APPROVED" or r.state == "CHANGES_REQUESTED")
      and (not best or (r.submittedAt or "") >= (best.at or "")) then
      best = { state = r.state, commit = r.commit and r.commit.oid, at = r.submittedAt }
    end
  end
  return best
end

-- Numeric review id (REST pull_request_review_id) from a GraphQL review node id.
-- New-style ids are "PRR_" + base64url(msgpack [0, repo_id, review_id]). → number|nil
function M.review_db_id(node_id)
  local b64 = type(node_id) == "string" and node_id:match("^PRR_(.+)$")
  if not b64 then return nil end
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  local bits, nbits, bytes = 0, 0, {}
  for ch in b64:gmatch("[^=]") do
    local v = alphabet:find(ch, 1, true) or (ch == "+" and 63) or (ch == "/" and 64)
    if not v then return nil end
    bits, nbits = bits * 64 + (v - 1), nbits + 6
    if nbits >= 8 then
      nbits = nbits - 8
      local byte = math.floor(bits / 2 ^ nbits)
      bytes[#bytes + 1] = string.char(byte)
      bits = bits - byte * 2 ^ nbits
    end
  end
  local raw = table.concat(bytes)
  local pos = 1
  local function int()
    local t = raw:byte(pos)
    if not t then return nil end
    if t <= 0x7f then pos = pos + 1 return t end
    local size = ({ [0xcc] = 1, [0xcd] = 2, [0xce] = 4, [0xcf] = 8 })[t]
    if not size or pos + size > #raw then return nil end
    local v = 0
    for i = 1, size do v = v * 256 + raw:byte(pos + i) end
    pos = pos + 1 + size
    return v
  end
  local head = raw:byte(pos)
  if not head or head < 0x91 or head > 0x9f then return nil end
  pos = pos + 1
  local last
  for _ = 1, head - 0x90 do
    last = int()
    if not last then return nil end
  end
  return last
end

-- REST review comments grouped under the review that submitted them.
-- reviews: GraphQL (id, author.login, submittedAt); comments: REST.
-- → { [review] = { comment, ... } } keyed by the review table.
function M.review_comment_groups(reviews, comments)
  local by_rid = {}
  for _, c in ipairs(comments or {}) do
    local rid = c.pull_request_review_id
    if rid then
      by_rid[rid] = by_rid[rid] or {}
      table.insert(by_rid[rid], c)
    end
  end
  local out, used = {}, {}
  for _, r in ipairs(reviews or {}) do
    local rid = M.review_db_id(r.id)
    if rid and by_rid[rid] then
      out[r], used[rid] = by_rid[rid], true
    end
  end
  -- Fallback (old-style ids): the author's first review submitted at or after
  -- the group's latest comment.
  for rid, group in pairs(by_rid) do
    if not used[rid] then
      local login = group[1].user and group[1].user.login
      local latest = ""
      for _, c in ipairs(group) do
        if (c.created_at or "") > latest then latest = c.created_at end
      end
      local best
      for _, r in ipairs(reviews or {}) do
        local at = r.submittedAt or ""
        if not out[r] and r.author and r.author.login == login and at >= latest
          and (not best or at < (best.submittedAt or "")) then
          best = r
        end
      end
      if best then out[best] = group end
    end
  end
  for _, group in pairs(out) do
    table.sort(group, function(x, y) return (x.created_at or "") < (y.created_at or "") end)
  end
  return out
end

return M
