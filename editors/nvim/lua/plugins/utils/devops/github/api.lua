---------------------------------------------------------------------------
-- GitHub API — via the authenticated `gh` CLI (no token handling here).
---------------------------------------------------------------------------

local config = require("plugins.utils.devops.config")

local M = {}

-- Fields available in `gh search prs --json`
local SEARCH_FIELDS = "number,title,url,state,isDraft,repository,author,createdAt,updatedAt"

-- Full fields for `gh pr view --json` (includes checks, branch)
local PR_FIELDS = "number,title,url,state,isDraft,statusCheckRollup,headRefName"

-- Run `gh <args>` expecting JSON on stdout. cb(ok, data, err)
local function gh_json(args, cb)
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(false, nil, (res.stderr ~= "" and res.stderr) or ("gh exited " .. res.code))
        return
      end
      local ok, data = pcall(vim.json.decode, res.stdout or "")
      if not ok then return cb(false, nil, "gh: invalid JSON output") end
      cb(true, data, nil)
    end)
  end)
end

function M.available() return vim.fn.executable("gh") == 1 end

-- Authenticated GitHub login (cached), for "(you)" markers. Fetched once.
local _user_login
function M.current_user_login() return _user_login end
function M.fetch_current_user(cb)
  if _user_login then if cb then cb(_user_login) end return end
  gh_json({ "api", "user" }, function(ok, data)
    if ok and type(data) == "table" and data.login then _user_login = data.login end
    if cb then cb(_user_login) end
  end)
end

local function limit() return tostring(config.options.github.pr_limit or 30) end

function M.notifications_count(cb)
  local cmd = { "gh", "api", "/notifications", "--jq", "length" }
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      local count = tonumber((res.stdout or ""):match("%d+")) or 0
      cb(count)
    end)
  end)
end

-- Open PRs authored by the current user.
function M.my_prs(cb)
  gh_json({ "search", "prs", "--author=@me", "--state=open", "--limit", limit(), "--json", SEARCH_FIELDS }, cb)
end

function M.search_prs(query, opts, cb)
  opts = opts or {}
  local args = { "search", "prs", "--state=open", "--limit", limit(), "--json", SEARCH_FIELDS }
  if opts.repo then
    vim.list_extend(args, { "--repo", opts.repo })
  end
  vim.list_extend(args, { "--", query })
  gh_json(args, cb)
end

-- Open PRs the current user is involved in (review-requested, author, assignee,
-- mentioned, or commenter). Uses GraphQL to include reviewRequests (user/team).
function M.my_reviews(cb)
  local n = config.options.github.pr_limit or 30
  local function do_fetch()
    local query = [[
query($n: Int!) {
  search(query: "is:pr is:open involves:@me", type: ISSUE, first: $n) {
    nodes {
      ... on PullRequest {
        number title url state isDraft headRefName
        repository { nameWithOwner name }
        author { login }
        createdAt updatedAt
        reviewRequests(first: 10) {
          nodes {
            requestedReviewer {
              ... on User { login }
              ... on Team { name }
            }
          }
        }
        reviews(last: 30) {
          nodes {
            author { login }
            state
            submittedAt
          }
        }
        reviewThreads(first: 60) {
          nodes {
            isResolved
            comments(first: 20) {
              nodes {
                author { login }
                createdAt
              }
            }
          }
        }
      }
    }
  }
}]]
    gh_json({ "api", "graphql", "-F", "n=" .. tostring(n), "-f", "query=" .. query }, function(ok, data, err)
      if not ok then return cb(false, nil, err) end
      local nodes = data and data.data and data.data.search and data.data.search.nodes
      if not nodes then return cb(false, nil, "unexpected GraphQL response") end
      local me = _user_login
      -- Normalize: extract reviewReason from reviewRequests
      for _, pr in ipairs(nodes) do
        local reasons = {}
        if pr.reviewRequests and pr.reviewRequests.nodes then
          for _, rr in ipairs(pr.reviewRequests.nodes) do
            local rev = rr.requestedReviewer
            if rev then
              reasons[#reasons + 1] = rev.login or rev.name or "?"
            end
          end
        end
        pr.reviewReason = #reasons > 0 and table.concat(reasons, ", ") or nil

        -- Derive approvedBy: list of users whose latest review is APPROVED
        pr.approvedBy = {}
        if pr.reviews and pr.reviews.nodes then
          -- Track latest review state per user
          local user_state = {} -- login → { state, ts }
          for _, rev in ipairs(pr.reviews.nodes) do
            local login = rev.author and rev.author.login
            if login then
              local ts = rev.submittedAt or ""
              if not user_state[login] or ts > user_state[login].ts then
                user_state[login] = { state = rev.state, ts = ts }
              end
            end
          end
          for login, info in pairs(user_state) do
            if info.state == "APPROVED" then
              pr.approvedBy[#pr.approvedBy + 1] = login
            end
          end
          table.sort(pr.approvedBy)
        end

        -- Derive comment/reply status from review threads
        -- awaiting_reply: I left a comment and no one replied after it
        -- replied: someone replied after my latest comment in a thread
        pr.commentStatus = nil -- nil | "awaiting_reply" | "replied"
        if me and pr.reviewThreads and pr.reviewThreads.nodes then
          local has_awaiting = false
          local has_replied = false
          for _, thread in ipairs(pr.reviewThreads.nodes) do
            if not thread.isResolved and thread.comments and thread.comments.nodes then
              local comments = thread.comments.nodes
              -- Find if I participated and what the last comment state is
              local my_last_idx = nil
              for i, c in ipairs(comments) do
                if c.author and c.author.login == me then
                  my_last_idx = i
                end
              end
              if my_last_idx then
                if my_last_idx == #comments then
                  -- My comment is the last one → awaiting reply
                  has_awaiting = true
                else
                  -- Someone commented after me → replied
                  has_replied = true
                end
              end
            end
          end
          if has_replied then
            pr.commentStatus = "replied"
          elseif has_awaiting then
            pr.commentStatus = "awaiting_reply"
          end
        end
      end
      cb(true, nodes, nil)
    end)
  end
  -- Ensure user login is resolved before fetching (needed for status detection)
  if _user_login then
    do_fetch()
  else
    M.fetch_current_user(function() do_fetch() end)
  end
end

-- Split the detail fetch: the "core" fields are light and render fast (the PR
-- description + status), while the heavy ones — CI checks and the paginating
-- files/commits/reviews/comments — load separately and fill in afterwards.
local PR_VIEW_CORE =
  "number,title,body,state,isDraft,url,headRefName,baseRefName,author," ..
  "additions,deletions,reviewDecision,labels,assignees,updatedAt," ..
  "reviewRequests,mergeStateStatus,mergeable"
local PR_VIEW_EXTRA = "statusCheckRollup,files,commits,reviews,comments"

-- Core PR details (fast). cb(ok, pr, err)
function M.pr_view(repo, number, cb)
  gh_json({ "pr", "view", tostring(number), "--repo", repo, "--json", PR_VIEW_CORE }, cb)
end

-- Heavy PR details, loaded after core. cb(ok, { statusCheckRollup, files,
-- commits, reviews, comments }, err)
function M.pr_view_extra(repo, number, cb)
  gh_json({ "pr", "view", tostring(number), "--repo", repo, "--json", PR_VIEW_EXTRA }, cb)
end

-- Inline review (code-thread) comments. cb(ok, comments[], err)
function M.pr_review_comments(repo, number, cb)
  gh_json({ "api", "repos/" .. repo .. "/pulls/" .. tostring(number) .. "/comments?per_page=100" }, cb)
end

function M.prs_for_issue(issue_key, cb)
  gh_json({
    "search", "prs",
    "--state=all",
    "--limit", "10",
    "--json", "number,title,url,state,isDraft,repository,author,headRefName",
    "--", issue_key,
  }, cb)
end

function M.pr_checks(repo, n, cb)
  gh_json({
    "pr", "checks", tostring(n),
    "--repo", repo,
    "--json", "name,state,conclusion,startedAt,completedAt,detailsUrl",
  }, cb)
end

---------------------------------------------------------------------------
-- PR write actions (non-JSON runner for operations returning plain text)
---------------------------------------------------------------------------
local function gh_run(args, cb, stdin)
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  local sysopts = { text = true }
  if stdin ~= nil then sysopts.stdin = stdin end
  vim.system(cmd, sysopts, function(res)
    vim.schedule(function()
      cb(res.code == 0, res.stdout or "", res.stderr or "")
    end)
  end)
end

function M.pr_approve(repo, n, cb)
  gh_run({ "pr", "review", tostring(n), "--repo", repo, "--approve" }, cb)
end

function M.pr_request_changes(repo, n, body, cb)
  gh_run({ "pr", "review", tostring(n), "--repo", repo, "--request-changes", "--body", body }, cb)
end

function M.pr_comment(repo, n, body, cb)
  gh_run({ "pr", "comment", tostring(n), "--repo", repo, "--body", body }, cb)
end

function M.pr_ready(repo, n, cb)
  gh_run({ "pr", "ready", tostring(n), "--repo", repo }, cb)
end

function M.pr_merge(repo, n, cb)
  gh_run({ "pr", "merge", tostring(n), "--repo", repo, "--squash" }, cb)
end

-- `gh pr diff` is re-fetched on every 'd' / 'F' / reopen and is ~0.6s+ (scales
-- with PR size). Cache it per repo#n with a short TTL so repeats are instant.
local diff_cache = {} -- [repo#n] = { text = ..., ts = os.time() }
local DIFF_TTL = 90   -- seconds

function M.pr_diff(repo, n, cb)
  local key = repo .. "#" .. tostring(n)
  local e = diff_cache[key]
  if e and (os.time() - e.ts) < DIFF_TTL then
    return vim.schedule(function() cb(true, e.text, "") end)
  end
  gh_run({ "pr", "diff", tostring(n), "--repo", repo }, function(ok, text, err)
    if ok then diff_cache[key] = { text = text, ts = os.time() } end
    cb(ok, text, err)
  end)
end

-- Drop cached diffs (all, or one repo#n) — e.g. on manual refresh.
function M.clear_diff_cache(repo, n)
  if repo and n then
    diff_cache[repo .. "#" .. tostring(n)] = nil
  else
    for k in pairs(diff_cache) do diff_cache[k] = nil end
  end
end

function M.pr_checkout(repo, n, cb)
  gh_run({ "pr", "checkout", tostring(n), "--repo", repo }, cb)
end

function M.pr_create(title, body, base, cb)
  local args = { "pr", "create", "--title", title, "--body", body or "" }
  if base and base ~= "" then
    vim.list_extend(args, { "--base", base })
  end
  gh_run(args, cb)
end

-- Submit a PR review with optional inline comments.
-- event: "COMMENT" | "APPROVE" | "REQUEST_CHANGES"
-- comments: list of { path, line, body } (can be empty)
function M.pr_review(repo, n, event, body, comments, cb)
  if #comments == 0 then
    local flag = event == "APPROVE" and "--approve"
      or event == "REQUEST_CHANGES" and "--request-changes"
      or "--comment"
    local args = { "pr", "review", tostring(n), "--repo", repo, flag }
    if body and body ~= "" then
      vim.list_extend(args, { "--body", body })
    elseif flag ~= "--approve" then
      vim.list_extend(args, { "--body", " " })
    end
    gh_run(args, cb)
  else
    -- Build JSON payload and write to temp file for gh api --input
    local api_comments = {}
    for _, c in ipairs(comments) do
      api_comments[#api_comments + 1] = {
        path = c.path,
        line = c.line,
        side = "RIGHT",
        body = c.body,
      }
    end
    local payload = vim.json.encode({
      event = event,
      body = (body and body ~= "") and body or " ",
      comments = api_comments,
    })
    -- Stream the payload on stdin ("--input -") instead of staging a temp file:
    -- nothing to clean up, and no silent no-op when the write fails.
    gh_run({
      "api", "repos/" .. repo .. "/pulls/" .. tostring(n) .. "/reviews",
      "--method", "POST",
      "--input", "-",
    }, cb, payload)
  end
end

return M
