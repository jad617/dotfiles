---------------------------------------------------------------------------
-- CI job log viewer — `gh run view --job <id> --log[-failed]` in a float.
---------------------------------------------------------------------------

local gh = require("plugins.utils.devops.github.api")
local errors = require("plugins.utils.devops.ui.errors")

local M = {}

-- "https://github.com/o/r/actions/runs/123/job/456" → "o/r", "123", "456"
function M.parse_url(url)
  local repo, run, job = (url or ""):match("github%.com/([^/]+/[^/]+)/actions/runs/(%d+)/job/(%d+)")
  if repo then return repo, run, job end
  repo, run = (url or ""):match("github%.com/([^/]+/[^/]+)/actions/runs/(%d+)")
  return repo, run, nil
end

-- ── parsing ────────────────────────────────────────────────────────────────
-- gh prints "job<TAB>step<TAB>2024-01-01T00:00:00.1234567Z text". Recent gh
-- versions label every line "UNKNOWN STEP", so steps are also recovered from
-- the runner's own markers: "##[group]Run <step>" opens a step (its group holds
-- the step's script/env), "Post job cleanup." and "Cleaning up orphan
-- processes" open the post / complete steps. Other groups become foldable
-- sub-groups.

local function ts_secs(ts)
  local y, mo, d, h, mi, sec = (ts or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):([%d%.]+)Z")
  if not y then return nil end
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = 0 }) + tonumber(sec)
end

function M.fmt_dur(secs)
  if not secs then return nil end
  secs = math.floor(secs + 0.5)
  if secs < 60 then return secs .. "s" end
  if secs < 3600 then return string.format("%dm %ds", secs / 60, secs % 60) end
  return string.format("%dh %dm", secs / 3600, (secs % 3600) / 60)
end

local function classify(msg)
  local tag, rest = msg:match("^##%[(%a+)%](.*)$")
  if tag == "error" then return "error", rest end
  if tag == "warning" then return "warning", rest end
  if tag == "notice" then return "notice", rest end
  if tag == "debug" then return "debug", rest end
  if tag == "command" then return "cmd", rest end
  local cmd = msg:match("^%[command%](.*)$")
  if cmd then return "cmd", cmd end
  local low = msg:lower()
  if low:find("^%s*error[:%s%[]") or low:find(":%d+:?%d*:? error[:%s]") or msg:find("%f[%w]ERROR%f[%W]")
    or msg:find("^%s*FAIL%f[%W]") or msg:find("^%s*%-%-%- FAIL") then
    return "error", msg
  end
  if low:find("^%s*warning[:%s%[]") or low:find(":%d+:?%d*:? warning[:%s]") then return "warning", msg end
  return "text", msg
end

-- → { steps = { { name, lines = { {text, kind} }, groups = { {from, to, name, config} },
--                errors, warnings, secs } }, errors, warnings }
function M.parse(text)
  local steps, cur, group = {}, nil, nil
  local function new_step(name)
    if group and cur then cur.groups[#cur.groups + 1] = { from = group.from, to = #cur.lines, name = group.name, config = group.config } end
    group = nil
    cur = { name = name, lines = {}, groups = {}, errors = 0, warnings = 0 }
    steps[#steps + 1] = cur
    return cur
  end
  local function add(t, kind)
    cur.lines[#cur.lines + 1] = { text = t, kind = kind }
    if kind == "error" then cur.errors = cur.errors + 1 end
    if kind == "warning" then cur.warnings = cur.warnings + 1 end
  end
  for raw in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local _, st, msg = raw:match("^([^\t]*)\t([^\t]*)\t(.*)$")
    msg = (msg or raw):gsub("^\239\187\191", "")
    local ts = msg:match("^(%d%d%d%d%-%d%d%-%d%dT[%d:%.]+Z)%s?")
    if ts then msg = msg:sub(#ts + 1):gsub("^ ", "") end
    local script = msg:find("[36;1m", 1, true) ~= nil
    -- gh prints ESC as a literal "^[" text, so strip both forms of SGR codes.
    msg = msg:gsub("\27%[[%d;?]*[A-Za-z]", ""):gsub("%^%[%[[%d;?]*[A-Za-z]", ""):gsub("\r", "")
      -- Runner paths eat the width: the checkout → "./", the temp dir → "$RUNNER_TEMP/".
      :gsub("/home/runner/work/_temp/[%x%-]+/", "$RUNNER_TEMP/")
      :gsub("/home/runner/work/([^/]+)/%1/", "./")
    local named = st and st ~= "" and st ~= "UNKNOWN STEP"
    if named and (not cur or cur.gh_name ~= st) then new_step(st).gh_name = st end
    if not (raw == "" and not cur) then
      if not cur then new_step("Set up job") end
      local gname = msg:match("^##%[group%](.*)$")
      if gname then
        if group then cur.groups[#cur.groups + 1] = { from = group.from, to = #cur.lines, name = group.name, config = group.config } end
        if not named and gname:match("^Run ") then
          new_step(gname)
          group = { from = 1, name = "details", config = true }
          add("details", "group")
        else
          add(gname, "group")
          group = { from = #cur.lines, name = gname }
        end
      elseif msg:match("^##%[endgroup%]") then
        if group then cur.groups[#cur.groups + 1] = { from = group.from, to = #cur.lines, name = group.name, config = group.config } end
        group = nil
      elseif not named and msg == "Post job cleanup." then
        if cur.name ~= "Post job cleanup" then new_step("Post job cleanup") end
      elseif not named and msg == "Cleaning up orphan processes" and cur.name ~= "Complete job" then
        new_step("Complete job")
        add(msg, "text")
      else
        local kind, t = classify(msg)
        if group and group.config and kind == "text" then kind = script and "script" or "config" end
        add(t, kind)
      end
      if ts then
        local secs = ts_secs(ts)
        cur.t0 = cur.t0 or secs
        cur.t1 = secs or cur.t1
      end
    end
  end
  if group and cur then cur.groups[#cur.groups + 1] = { from = group.from, to = #cur.lines, name = group.name, config = group.config } end
  local out = { steps = {}, errors = 0, warnings = 0 }
  for i, step in ipairs(steps) do
    while #step.lines > 0 and step.lines[#step.lines].text == "" do step.lines[#step.lines] = nil end
    local nxt = steps[i + 1]
    local t1 = (nxt and nxt.t0) or step.t1
    step.secs = step.t0 and t1 and math.max(0, t1 - step.t0) or nil
    -- Groups that end past trimmed lines, or that hold nothing, can't fold.
    local kept = {}
    for _, g in ipairs(step.groups) do
      g.to = math.min(g.to, #step.lines)
      if g.to > g.from then kept[#kept + 1] = g end
    end
    step.groups = kept
    if #step.lines > 0 or step.errors > 0 then
      out.steps[#out.steps + 1] = step
      out.errors, out.warnings = out.errors + step.errors, out.warnings + step.warnings
    end
  end
  return out
end

-- ── rendering ──────────────────────────────────────────────────────────────

local SH_KEYWORDS = {}
for w in ([[if then else elif fi for while until do done case esac in function return
  export source set unset local exit echo printf cd test eval exec shift trap]]):gmatch("%S+") do
  SH_KEYWORDS[w] = true
end

-- Token highlights inside one log line → { {from, to, hl} } (0-based, end-exclusive).
-- Later spans win (applied with rising priority).
function M.tokens(text, kind)
  local spans = {}
  local function add(a, b, hl) if b > a then spans[#spans + 1] = { a, b, hl } end end
  local function each(pat, hl, group)
    local init = 1
    while true do
      local a, b, cap = text:find(pat, init)
      if not a then break end
      if group and cap then
        local ca = text:find(cap, a, true)
        add(ca - 1, ca - 1 + #cap, hl)
      else
        add(a - 1, b, hl)
      end
      init = b + 1
    end
  end
  -- numbers / versions / durations / sizes
  each("%f[%w%._]%d[%d%.]*%a?%a?%f[^%w%._]", "DevOpsLogNum")
  -- quoted strings
  each('"[^"]*"', "DevOpsLogStr")
  each("'[^']*'", "DevOpsLogStr")
  -- $VAR / ${VAR}
  each("%$%b{}", "DevOpsLogVar")
  each("%$[%a_][%w_]*", "DevOpsLogVar")
  -- file paths with an optional :line:col
  each("[%$%w_%.%-~]*/[%w_%.%-/@+]+%.%a[%w]*:?%d*:?%d*", "DevOpsLogPath")
  each("%f[%w_%.%-][%w_%-]+%.%a%a?%a?%a?:%d+:?%d*", "DevOpsLogPath")
  -- URLs
  each("https?://[%w%-%._~:/%?#%[%]@!%$&'%(%)%*%+,;=%%]+", "DevOpsLogUrl")
  -- sha
  each("%f[%x]%x%x%x%x%x%x%x+%f[^%x]", "DevOpsLogNum")

  if kind == "script" then
    local init = 1
    while true do
      local a, b = text:find("[%a_][%w_%-]*", init)
      if not a then break end
      if SH_KEYWORDS[text:sub(a, b)] and (a == 1 or text:sub(a - 1, a - 1):match("[%s;(|&]")) then
        add(a - 1, b, "DevOpsLogKeyword")
      end
      init = b + 1
    end
    local c = text:find("%f[#]#[^!{]") or (text:find("^#") and 1)
    if c and (c == 1 or text:sub(c - 1, c - 1):match("%s")) then add(c - 1, #text, "DevOpsDim") end
  elseif kind == "config" then
    local a, b = text:find("^%s*[%w_%-%.]+:")
    if a then add(a - 1, b, "DevOpsLogKey") end
  elseif kind ~= "group" and kind ~= "cmd" then
    -- "key: value" / "Key=Value" log lines
    local a, b = text:find("^%s*[%a][%w_%- ]-:%s")
    if a and b - a < 30 then add(a - 1, b - 1, "DevOpsLogKey") end
    -- compiler / test words
    for _, w in ipairs({ { "error", "DevOpsErr" }, { "ERROR", "DevOpsErr" }, { "FAIL", "DevOpsErr" },
      { "FAILED", "DevOpsErr" }, { "failed", "DevOpsErr" }, { "fatal", "DevOpsErr" },
      { "warning", "DevOpsWarn" }, { "WARN", "DevOpsWarn" }, { "deprecated", "DevOpsWarn" },
      { "note", "DevOpsSection" }, { "hint", "DevOpsSection" },
      { "PASS", "DevOpsOk" }, { "PASSED", "DevOpsOk" }, { "ok", "DevOpsOk" }, { "OK", "DevOpsOk" },
      { "success", "DevOpsOk" }, { "successfully", "DevOpsOk" }, { "Done", "DevOpsOk" } }) do
      each("%f[%w]" .. w[1] .. "%f[%W]", w[2])
    end
    -- compiler caret lines "    ~~~~^~~~"
    if text:match("^%s*[~%^]+%s*$") then add(#text:match("^%s*"), #text, "DevOpsErr") end
  end
  return spans
end

-- Lay the parsed log out as buffer lines + decorations.
-- → { lines, marks = { {row, opts} }, folds = { {from, to, open} }, foldtext = { [row] = chunks },
--     first_err, errors = {rows}, headers = {rows} }   (rows are 1-based)
function M.layout(log)
  local L = { lines = {}, marks = {}, folds = {}, foldtext = {}, errors = {}, headers = {},
    raw = {}, step_of = {}, steps = {} } -- raw[row] = log text; step_of[row] = step index; steps[si] = {from, to}
  local function push(t) L.lines[#L.lines + 1] = t; return #L.lines end
  local function mark(row, opts) L.marks[#L.marks + 1] = { row, opts } end

  local failed = 0
  local total = 0
  for _, st in ipairs(log.steps) do
    if st.errors > 0 then failed = failed + 1 end
    total = total + (st.secs or 0)
  end
  local sum = {}
  local function chunk(t, hl) sum[#sum + 1] = { t, hl } end
  chunk("  ", nil)
  if failed > 0 then
    chunk("✗ " .. failed .. " failed step" .. (failed == 1 and "" or "s"), "DevOpsErr")
  else
    chunk("✓ no errors", "DevOpsOk")
  end
  if log.errors > 0 then chunk("  ·  ", "DevOpsDim"); chunk(log.errors .. " error line" .. (log.errors == 1 and "" or "s"), "DevOpsErr") end
  if log.warnings > 0 then
    chunk("  ·  ", "DevOpsDim"); chunk("⚠ " .. log.warnings .. " warning" .. (log.warnings == 1 and "" or "s"), "DevOpsWarn")
  end
  chunk("  ·  " .. #log.steps .. " steps", "DevOpsDim")
  if total > 0 then chunk("  ·  " .. M.fmt_dur(total), "DevOpsDim") end
  local text = ""
  for _, c in ipairs(sum) do text = text .. c[1] end
  local r = push(text)
  local col = 0
  for _, c in ipairs(sum) do
    if c[2] then mark(r, { col = col, end_col = col + #c[1], hl_group = c[2] }) end
    col = col + #c[1]
  end
  push("")

  for si, st in ipairs(log.steps) do
    local bad = st.errors > 0
    local icon = bad and "✗" or "✓"
    local hdr_hl = bad and "DevOpsLogStepFail" or "DevOpsLogStep"
    local meta_hl = bad and "DevOpsLogStepFailMeta" or "DevOpsLogStepMeta"
    local meta = {}
    if st.warnings > 0 then meta[#meta + 1] = "⚠ " .. st.warnings end
    meta[#meta + 1] = #st.lines .. " line" .. (#st.lines == 1 and "" or "s")
    if st.secs then meta[#meta + 1] = M.fmt_dur(st.secs) end
    local meta_s = table.concat(meta, " · ") .. "  "
    local chev = "▾ "
    local head = chev .. icon .. "  " .. st.name
    local h = push(head)
    L.headers[#L.headers + 1] = h
    local icon_hl = bad and "DevOpsErr" or "DevOpsOk"
    mark(h, { col = 0, end_col = #head, hl_group = hdr_hl })
    mark(h, { col = #chev, end_col = #chev + #icon, hl_group = icon_hl })
    mark(h, { col = 0, virt_text = { { meta_s, meta_hl } }, virt_text_pos = "right_align" })
    L.foldtext[h] = { { "▸ ", hdr_hl }, { icon, icon_hl }, { "  " .. st.name, hdr_hl },
      fill = hdr_hl, right = { meta_s, meta_hl } }

    local base = h
    L.step_of[h] = si
    L.steps[si] = { from = h + 1, to = h + #st.lines }
    local foldable = {}
    for _, g in ipairs(st.groups) do foldable[g.from] = true end
    for i, ln in ipairs(st.lines) do
      local row = push(ln.text)
      L.raw[row], L.step_of[row] = ln.text, si
      local gut, ghl = "   ", "DevOpsLogLineNr"
      if ln.kind == "error" then
        gut, ghl = " ✗ ", "DevOpsErr"
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsLogErrLine" })
        L.errors[#L.errors + 1] = row
        L.first_err = L.first_err or row
      elseif ln.kind == "warning" then
        gut, ghl = " ⚠ ", "DevOpsWarn"
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsLogWarnLine" })
      elseif ln.kind == "cmd" then
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsLogCmd" })
        gut = " $ "
      elseif ln.kind == "group" then
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsLogGroup" })
        gut = foldable[i] and " ▾ " or " · "
        ghl = "DevOpsLogGroup"
      elseif ln.kind == "script" then
        gut, ghl = " │ ", "DevOpsLogCmd"
      elseif ln.kind == "config" or ln.kind == "debug" then
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsDim" })
      elseif ln.kind == "notice" then
        mark(row, { col = 0, end_col = #ln.text, hl_group = "DevOpsSection" })
      end
      if ln.kind ~= "group" then
        for k, sp in ipairs(M.tokens(ln.text, ln.kind)) do
          mark(row, { col = sp[1], end_col = sp[2], hl_group = sp[3], priority = 4200 + k })
        end
      end
      mark(row, { col = 0, virt_text = { { string.format("%6d", i), "DevOpsLogLineNr" }, { gut, ghl } },
        virt_text_pos = "inline" })
    end
    for _, g in ipairs(st.groups) do
      local from, to = base + g.from, base + g.to
      L.folds[#L.folds + 1] = { from = from, to = to, open = false }
      L.foldtext[from] = { { string.format("%6d", g.from), "DevOpsLogLineNr" }, { " ▸ ", "DevOpsLogGroup" },
        { st.lines[g.from].text, "DevOpsLogGroup" }, { "  " .. (g.to - g.from) .. (g.to - g.from == 1 and " line" or " lines"), "DevOpsDim" } }
    end
    if #st.lines > 0 then
      L.folds[#L.folds + 1] = { from = h, to = h + #st.lines, open = bad, step = true }
    end
    if si < #log.steps then push("") end
  end
  return L
end

-- ── source references / copy ───────────────────────────────────────────────

-- The file reference on a log line: the one under byte `col` (0-based), else the
-- first. Handles "path:line[:col]" and Python's 'File "path", line N'.
-- → path, line, col | nil
function M.find_ref(text, col)
  text = text or ""
  local py, pyl = text:match('File "([^"]+)", line (%d+)')
  if py then return py, tonumber(pyl), 1 end
  local first
  local init = 1
  while true do
    local s, e, path, ln, c = text:find("([%w%._%-/$~]*[%w_%-]%.%a[%w]*):(%d+):?(%d*)", init)
    if not s then break end
    local ref = { path, tonumber(ln), tonumber(c) or 1 }
    first = first or ref
    if col and col >= s - 1 and col < e then return ref[1], ref[2], ref[3] end
    init = e + 1
  end
  if first then return first[1], first[2], first[3] end
end

-- Map a log path onto the local checkout at `root`: exact (after "./"), else
-- the file whose path ends with it (runner paths may carry extra prefixes).
function M.resolve(path, root)
  if not path or path == "" then return nil end
  path = path:gsub("^%./", ""):gsub("^%$RUNNER_TEMP/", "")
  if path:sub(1, 1) == "/" and vim.uv.fs_stat(path) then return path end
  root = root or vim.fn.getcwd()
  local direct = root .. "/" .. path
  if vim.uv.fs_stat(direct) then return direct end
  local rel = path:gsub("^/+", "")
  local base = vim.fs.basename(rel)
  local best, best_len
  for _, f in ipairs(vim.fs.find(base, { path = root, type = "file", limit = 50 })) do
    -- Longest common path suffix wins.
    local a, b = vim.split(f, "/"), vim.split(rel, "/")
    local n = 0
    while n < #a and n < #b and a[#a - n] == b[#b - n] do n = n + 1 end
    if n > 0 and (not best_len or n > best_len) then best, best_len = f, n end
  end
  return best
end

-- Rows (1-based, inclusive) of the error block at `row`: the line and what
-- follows it up to the next error, blank line or step end (max 40 lines).
function M.error_block(L, row)
  local si = L.step_of[row]
  if not si or not L.raw[row] then return nil end
  local is_err = {}
  for _, r in ipairs(L.errors) do is_err[r] = true end
  local last = row
  while last + 1 <= L.steps[si].to and last - row < 39 and not is_err[last + 1]
    and L.raw[last + 1] and vim.trim(L.raw[last + 1]) ~= "" do
    last = last + 1
  end
  return row, last
end

local function copy(lines, what)
  local text = table.concat(lines, "\n")
  vim.fn.setreg('"', text)
  pcall(vim.fn.setreg, "+", text)
  vim.notify(string.format("DevOps: copied %s (%d line%s)", what, #lines, #lines == 1 and "" or "s"), vim.log.levels.INFO)
end

-- Open `path` at line/col in a regular window (the dashboard float steps aside).
local function edit_at(path, line, col)
  pcall(function() require("plugins.utils.devops.ui.dashboard").hide_float() end)
  pcall(function() require("plugins.utils.devops.ui.detail").close_float() end)
  local target
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
      target = w; break
    end
  end
  if target then vim.api.nvim_set_current_win(target) end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, math.max(0, (col or 1) - 1) })
  vim.cmd("normal! zz")
end

-- ── re-run ─────────────────────────────────────────────────────────────────

-- Ask what to re-run for a job/run URL, then trigger it.
function M.rerun(url, on_done)
  local repo, run, job = M.parse_url(url)
  if not run then return vim.notify("DevOps: not a GitHub Actions run", vim.log.levels.INFO) end
  local choices = { { "failed", "Re-run failed jobs" } }
  if job then choices[#choices + 1] = { "job", "Re-run this job" } end
  choices[#choices + 1] = { "all", "Re-run all jobs" }
  vim.ui.select(choices, { prompt = "Re-run run #" .. run, format_item = function(c) return c[2] end }, function(c)
    if not c then return end
    gh.run_rerun(repo, run, c[1], job, function(ok, _, err)
      if not ok then return errors.show("DevOps: re-run failed — " .. vim.trim(err or "?")) end
      vim.notify("DevOps: " .. c[2]:lower() .. " queued for run #" .. run, vim.log.levels.INFO)
      if on_done then on_done() end
    end)
  end)
end

local ns = vim.api.nvim_create_namespace("DevOpsJobLog")
-- Float geometry: centred ~90%×85%, or the whole editor when zoomed.
function M.geometry(zoomed)
  local cols, lines = vim.o.columns, vim.o.lines - vim.o.cmdheight
  if zoomed then
    return { relative = "editor", row = 0, col = 0, width = math.max(1, cols - 2), height = math.max(1, lines - 2) }
  end
  local width = math.min(cols - 4, math.max(80, math.floor(cols * 0.9)))
  local height = math.max(10, math.floor(vim.o.lines * 0.85))
  return { relative = "editor", width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1, col = math.floor((cols - width) / 2) }
end

local fold_text = {} -- [buf] = { [row] = chunks }

-- 'foldtext' for the log float: a closed step keeps its header bar look.
function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local spec = fold_text[buf] and fold_text[buf][vim.v.foldstart]
  if not spec then return vim.fn.foldtext() end
  local chunks = {}
  local used = 0
  for _, c in ipairs(spec) do chunks[#chunks + 1] = c; used = used + vim.fn.strdisplaywidth(c[1]) end
  if spec.fill then
    local width = vim.api.nvim_win_get_width(0)
    local right = spec.right and spec.right[1] or ""
    local pad = width - used - vim.fn.strdisplaywidth(right)
    if pad > 0 then chunks[#chunks + 1] = { string.rep(" ", pad), spec.fill } end
    if spec.right then chunks[#chunks + 1] = spec.right end
  end
  return chunks
end

local function key_footer(keys)
  local out = { { " ", "DevOpsDim" } }
  for i, k in ipairs(keys) do
    if i > 1 then out[#out + 1] = { "  ", "DevOpsDim" } end
    out[#out + 1] = { k[1], "DevOpsKey" }
    out[#out + 1] = { " " .. k[2], "DevOpsDim" }
  end
  out[#out + 1] = { " ", "DevOpsDim" }
  return out
end

local function show(title, log, url)
  local L = M.layout(log)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, L.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "devops_log"
  for _, m in ipairs(L.marks) do
    local opts = vim.deepcopy(m[2])
    local col = opts.col or 0
    opts.col = nil
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1] - 1, col, opts)
  end
  fold_text[buf] = L.foldtext
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = function() fold_text[buf] = nil end })

  local bad = log.errors > 0
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", M.geometry(false), {
    -- Just above the dashboard (50) so notifications / pickers aren't hidden.
    style = "minimal", border = "rounded", zindex = 60,
    title = { { " " .. (bad and "✗" or "✓") .. " ", bad and "DevOpsErr" or "DevOpsOk" }, { title .. " ", "DevOpsTitle" } },
    title_pos = "center",
    footer = key_footer({ { "]e/[e", "error" }, { "]s/[s", "step" }, { "↵", "fold" }, { "zR/zM", "all" },
      { "gf", "source" }, { "y/Y", "copy" }, { "r", "re-run" }, { "w", "wrap" }, { "␣z", "zoom" },
      { "o", "browser" }, { "q", "close" } }),
    footer_pos = "center",
  }))
  -- Same surface as the dashboard: the colorscheme's Normal, not NormalFloat.
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsLogBorder,FloatTitle:DevOpsTitle,Folded:Normal"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].foldmethod = "manual"
  vim.wo[win].foldenable = true
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].fillchars = "fold: ,eob: "
  vim.wo[win].foldtext = "v:lua.require'plugins.utils.devops.ui.job_log'.foldtext()"
  vim.wo[win].sidescrolloff = 0

  vim.api.nvim_win_call(win, function()
    -- Inner groups first so the step folds nest around them; then open the
    -- failed steps (their groups stay closed, like GitHub).
    table.sort(L.folds, function(a, b) return (a.to - a.from) < (b.to - b.from) end)
    for _, f in ipairs(L.folds) do vim.cmd(string.format("silent! %d,%dfold", f.from, f.to)) end
    for _, f in ipairs(L.folds) do
      if f.step and f.open then vim.cmd(string.format("silent! %dfoldopen", f.from)) end
    end
  end)

  local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  -- Leaving the float (another window, picker, split…) closes it, so nothing
  -- ends up stacked behind a stale log.
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf, once = true,
    callback = function() vim.schedule(close) end,
  })
  local function goto_row(row)
    vim.api.nvim_win_set_cursor(win, { row, 0 })
    vim.cmd("normal! zv")
  end
  local function jump(list, dir)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    if dir > 0 then
      for _, r in ipairs(list) do if r > cur then return goto_row(r) end end
    else
      for i = #list, 1, -1 do if list[i] < cur then return goto_row(list[i]) end end
    end
  end
  local function step_jump(dir)
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    -- From inside a closed fold, line numbers are of its first row.
    local closed = vim.fn.foldclosed(cur)
    if closed ~= -1 then cur = closed end
    if dir > 0 then
      for _, r in ipairs(L.headers) do if r > cur then return vim.api.nvim_win_set_cursor(win, { r, 0 }) end end
    else
      for i = #L.headers, 1, -1 do if L.headers[i] < cur then return vim.api.nvim_win_set_cursor(win, { L.headers[i], 0 }) end end
    end
  end
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, o)
  vim.keymap.set("n", "<C-d>", close, o)
  vim.keymap.set("n", "<Esc>", close, o)
  vim.keymap.set("n", "o", function() if url then vim.ui.open(url) end end, o)
  vim.keymap.set("n", "]e", function() jump(L.errors, 1) end, o)
  vim.keymap.set("n", "[e", function() jump(L.errors, -1) end, o)
  vim.keymap.set("n", "]s", function() step_jump(1) end, o)
  vim.keymap.set("n", "[s", function() step_jump(-1) end, o)
  vim.keymap.set("n", "<CR>", "za", o)
  vim.keymap.set("n", "<Tab>", "za", o)
  vim.keymap.set("n", "w", function() vim.wo[win].wrap = not vim.wo[win].wrap end, o)
  vim.keymap.set("n", "r", function() M.rerun(url) end, o)
  vim.keymap.set("n", "gf", function()
    local cur = vim.api.nvim_win_get_cursor(win)
    local text = L.raw[cur[1]]
    -- The inline line-number gutter isn't buffer text, so the cursor col maps 1:1.
    local path, line, col = M.find_ref(text, cur[2])
    if not path then return vim.notify("DevOps: no file:line on this line", vim.log.levels.INFO) end
    local root = vim.fs.root(0, ".git") or vim.fs.root(vim.fn.getcwd(), ".git") or vim.fn.getcwd()
    local file = M.resolve(path, root)
    if not file then return vim.notify("DevOps: " .. path .. " not found under " .. root, vim.log.levels.WARN) end
    close()
    edit_at(file, line, col)
  end, o)
  vim.keymap.set("n", "y", function()
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local a, b = M.error_block(L, row)
    if not a then return end
    local out = {}
    for r = a, b do out[#out + 1] = L.raw[r] end
    copy(out, "error block")
  end, o)
  vim.keymap.set("n", "Y", function()
    local si = L.step_of[vim.api.nvim_win_get_cursor(win)[1]]
    if not si then return end
    local out = {}
    for r = L.steps[si].from, L.steps[si].to do out[#out + 1] = L.raw[r] or "" end
    copy(out, "step \"" .. log.steps[si].name .. "\"")
  end, o)
  -- Zoom in place: a global zoom (Snacks.zen on <leader>z) opens another
  -- window, which the WinLeave guard above treats as leaving → closes the log.
  local zoomed = false
  local function zoom()
    zoomed = not zoomed
    pcall(vim.api.nvim_win_set_config, win, M.geometry(zoomed))
  end
  vim.keymap.set("n", "<leader>z", zoom, vim.tbl_extend("force", o, { desc = "Zoom log" }))
  vim.keymap.set("n", "<leader>Z", zoom, vim.tbl_extend("force", o, { desc = "Zoom log" }))
  vim.api.nvim_create_autocmd("VimResized", {
    buffer = buf,
    callback = function() pcall(vim.api.nvim_win_set_config, win, M.geometry(zoomed)) end,
  })
  goto_row(L.first_err or 1)
  vim.cmd("normal! zz")
  return buf, win, L
end

-- Open the log of a check (statusCheckRollup context). Non-Actions checks
-- (external CI) open their page in the browser.
-- ── live view (job still running: logs aren't downloadable yet) ────────────

local function iso_secs(ts)
  local y, mo, d, h, mi, sec = (ts or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  -- UTC → epoch (os.time reads local time; correct by the current offset).
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) })
  local now = os.time()
  return t + os.difftime(now, os.time(os.date("!*t", now)))
end

local STEP_ICON = {
  success = { "✓", "DevOpsOk" }, failure = { "✗", "DevOpsErr" }, cancelled = { "⊘", "DevOpsDim" },
  skipped = { "↷", "DevOpsDim" }, timed_out = { "✗", "DevOpsErr" },
}

-- Lines + marks for a running job (`gh api …/actions/jobs/<id>`).
function M.live_layout(job, now)
  now = now or os.time()
  local lines, marks = {}, {}
  local function mark(row, s, e, hl) marks[#marks + 1] = { row, s, e, hl } end
  local steps = job.steps or {}
  local done, cur = 0, nil
  for _, st in ipairs(steps) do
    if st.status == "completed" then done = done + 1 elseif st.status == "in_progress" then cur = cur or st end
  end
  local t0 = iso_secs(job.started_at)
  local head = "  ⟳ " .. (job.status == "queued" and "queued" or "running")
    .. "  ·  step " .. math.min(done + 1, math.max(#steps, 1)) .. "/" .. #steps
    .. (t0 and ("  ·  " .. M.fmt_dur(math.max(0, now - t0))) or "")
  lines[1] = head
  mark(1, 0, #head, "DevOpsWarn")
  lines[2] = ""
  for _, st in ipairs(steps) do
    local ic = STEP_ICON[st.conclusion or ""] or (st.status == "in_progress" and { "⟳", "DevOpsWarn" }) or { "·", "DevOpsDim" }
    local a, b = iso_secs(st.started_at), iso_secs(st.completed_at)
    local dur = a and M.fmt_dur(math.max(0, (b or now) - a)) or ""
    local line = "  " .. ic[1] .. "  " .. (st.name or "?")
    lines[#lines + 1] = line
    local row = #lines
    mark(row, 2, 2 + #ic[1], ic[2])
    local name_hl = st.status == "in_progress" and "DevOpsLogStep" or (st.status == "completed" and "Normal" or "DevOpsDim")
    if st.conclusion == "failure" then name_hl = "DevOpsLogStepFail" end
    mark(row, 2 + #ic[1], #line, name_hl)
    if dur ~= "" then marks[#marks + 1] = { row, 0, 0, nil, dur } end
  end
  return lines, marks
end

local live_ns = vim.api.nvim_create_namespace("DevOpsJobLive")

-- Poll a running job every 3s, showing its steps; once it completes, the full
-- log replaces the view.
function M.live(repo, job_id, name, url, info)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "devops_log"
  local win = vim.api.nvim_open_win(buf, true, vim.tbl_extend("force", M.geometry(false), {
    style = "minimal", border = "rounded", zindex = 60,
    title = { { " ⟳ ", "DevOpsWarn" }, { name .. " · live ", "DevOpsTitle" } }, title_pos = "center",
    footer = key_footer({ { "r", "re-run" }, { "o", "browser" }, { "q", "close" } }), footer_pos = "center",
  }))
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:DevOpsLogBorder,FloatTitle:DevOpsTitle"
  vim.wo[win].cursorline = true
  local timer = vim.uv.new_timer()
  local closed = false
  local function stop()
    closed = true
    if timer then timer:stop(); if not timer:is_closing() then timer:close() end; timer = nil end
  end
  local function close()
    stop()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  local function paint(job)
    if closed or not vim.api.nvim_buf_is_valid(buf) then return end
    local lines, marks = M.live_layout(job)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, live_ns, 0, -1)
    for _, m in ipairs(marks) do
      if m[5] then
        pcall(vim.api.nvim_buf_set_extmark, buf, live_ns, m[1] - 1, 0,
          { virt_text = { { m[5] .. "  ", "DevOpsLogStepMeta" } }, virt_text_pos = "right_align" })
      else
        pcall(vim.api.nvim_buf_set_extmark, buf, live_ns, m[1] - 1, m[2], { end_col = m[3], hl_group = m[4] })
      end
    end
  end
  local function tick()
    gh.job_info(repo, job_id, function(ok, job)
      if closed then return end
      if not ok or type(job) ~= "table" then return end
      if job.status == "completed" then
        close()
        return M.open({ name = name, detailsUrl = url, status = "COMPLETED", conclusion = (job.conclusion or ""):upper() })
      end
      paint(job)
    end)
  end
  if info then paint(info) end
  timer:start(3000, 3000, vim.schedule_wrap(tick))
  if not info then tick() end
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function() vim.schedule(close) end })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, once = true, callback = stop })
  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, o)
  vim.keymap.set("n", "<C-d>", close, o)
  vim.keymap.set("n", "<Esc>", close, o)
  vim.keymap.set("n", "o", function() if url then vim.ui.open(url) end end, o)
  vim.keymap.set("n", "r", function() M.rerun(url) end, o)
  return buf, win, stop
end

local function running(ctx)
  local st = (ctx.status or ""):upper()
  if st ~= "" then return st ~= "COMPLETED" end
  return (ctx.state or ""):upper() == "PENDING" or (ctx.state or ""):upper() == "IN_PROGRESS"
end
M._running = running

function M.open(ctx)
  local url = ctx.detailsUrl or ctx.targetUrl or ctx.link
  local repo, _, job = M.parse_url(url)
  if not job then
    if url and url ~= "" then return vim.ui.open(url) end
    return vim.notify("DevOps: this check has no log or URL", vim.log.levels.INFO)
  end
  local name = require("plugins.utils.devops.ui.detail")._check_name(ctx)
  if running(ctx) then return M.live(repo, job, name, url) end
  local failed = ctx.conclusion == "FAILURE" or ctx.conclusion == "TIMED_OUT"
  vim.notify("DevOps: loading log for " .. name .. "…", vim.log.levels.INFO)
  local function done(ok, text, err)
    if not ok then return errors.show("DevOps: log failed — " .. (err or "?")) end
    local log = M.parse(text)
    if #log.steps == 0 then return M.live(repo, job, name, url) end
    show(name .. (failed and " · failed steps" or ""), log, url)
  end
  gh.job_log(repo, job, failed, function(ok, text, err)
    -- "still in progress; logs will be available when it is complete"
    if not ok and (err or ""):find("in progress", 1, true) then return M.live(repo, job, name, url) end
    -- --log-failed is empty when the failure wasn't in a step (e.g. setup) → full log
    if failed and ok and vim.trim(text) == "" then return gh.job_log(repo, job, false, done) end
    done(ok, text, err)
  end)
end

M._show = show
return M
