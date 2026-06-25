-- Standalone tests for the pure rendering helpers (no Neovim required).
-- Run:  luajit tests/run.lua   (from the devops/ dir, or any cwd)
--
-- These cover render.truncate/pad/fit and markdown.clean/render — the functions
-- that drove several alignment/wrapping regressions. The vim stub approximates
-- display width as the UTF-8 codepoint count (good enough for the logic; it does
-- not model wide CJK/emoji cells).

local here = (arg and arg[0] or ""):match("(.*/)") or "./"

-- ── minimal vim stub ───────────────────────────────────────────────────────
local function codepoints(s)
  local cps, i = {}, 1
  while i <= #s do
    local b = s:byte(i)
    local len = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
    cps[#cps + 1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return cps
end

local function split_nl(s)
  local t, start = {}, 1
  while true do
    local nl = s:find("\n", start, true)
    if not nl then t[#t + 1] = s:sub(start); break end
    t[#t + 1] = s:sub(start, nl - 1)
    start = nl + 1
  end
  return t
end

_G.vim = {
  fn = {
    strdisplaywidth = function(s) return #codepoints(s or "") end,
    nr2char = function(n) return string.char(n) end,
    split = function(s, sep)
      if sep == "\\zs" then return codepoints(s) end
      return split_nl(s)
    end,
  },
  split = function(s, _, _) return split_nl(s) end,
  api = setmetatable({
    nvim_set_hl = function() end,
    nvim_create_namespace = function() return 0 end,
    nvim_create_augroup = function() return 0 end,
  }, { __index = function() return function() end end }), -- any other api call is a noop
}

-- ── tiny assert framework ──────────────────────────────────────────────────
local passed, failed = 0, 0
local function ok(cond, name)
  if cond then passed = passed + 1
  else failed = failed + 1; print("  ✗ " .. name) end
end
local function eq(got, want, name)
  if got == want then passed = passed + 1
  else failed = failed + 1; print(("  ✗ %s\n      want: %q\n      got:  %q"):format(name, tostring(want), tostring(got))) end
end

local render = dofile(here .. "../ui/render.lua")
local md = dofile(here .. "../ui/markdown.lua")
local dw = vim.fn.strdisplaywidth

-- ── render.truncate / pad / fit ────────────────────────────────────────────
eq(render.truncate("hello", 10), "hello", "truncate: short string unchanged")
eq(render.truncate("abcdefgh", 4), "abc…", "truncate: ascii to width-1 + ellipsis")
eq(dw(render.truncate("ünïcodé-string", 6)), 6, "truncate: multibyte fits exactly")
ok(not render.truncate("ünïcodé", 4):find("\194\160"), "truncate: no stray bytes")
eq(render.pad("ab", 5), "ab   ", "pad: right-pads to width")
eq(render.pad("abcdef", 3), "abcdef", "pad: never shrinks")
eq(dw(render.fit("abcdefgh", 5)), 5, "fit: exact display width (truncate+pad)")
eq(dw(render.fit("ab", 5)), 5, "fit: pads short to width")

-- ── markdown.clean ─────────────────────────────────────────────────────────
eq(md.clean("a&nbsp;b"), "a b", "clean: &nbsp; → space")
eq(md.clean("a<br />b"), "a\nb", "clean: <br> → newline")
eq(md.clean("x <!-- hide --> y"), "x  y", "clean: HTML comment removed")
eq(md.clean("see [docs](http://x)"), "see docs", "clean: link → text")
eq(md.clean("[![alt](img.png)](http://x)"), "alt", "clean: linked badge → alt")
eq(md.clean("**bold** and __b2__"), "bold and b2", "clean: bold markers stripped")
eq(md.clean("a &ge; b"), "a &ge; b", "clean: leaves unknown entities (smoke)")

-- ── markdown.render ────────────────────────────────────────────────────────
local function lines(text, w) return md.render(md.clean(text), "", w).lines end

ok(lines("# Title")[1]:find("▌"), "render: header marker")
ok(lines("- item")[1]:find("•"), "render: bullet marker")
ok(lines("> quoted")[1]:find("▏"), "render: blockquote rail")
local hr = lines("---")[1]
ok(hr:find("─") and not hr:find("%w"), "render: horizontal rule (── divider)")

-- word-wrap to width: every line fits, and it wraps to >1 line
local wrapped = lines(("word "):rep(30), 20)
ok(#wrapped > 1, "render: long paragraph wraps")
local within = true
for _, l in ipairs(wrapped) do if dw(l) > 20 then within = false end end
ok(within, "render: wrapped lines fit the width")

-- table: header + separator + aligned rows, fits width
local tbl = lines("| A | Bee |\n|---|---|\n| 1 | 2 |", 40)
ok(tbl[2]:find("─"), "render: table header underline")
local taligned = true
for _, l in ipairs(tbl) do if dw(l) > 40 then taligned = false end end
ok(taligned, "render: table fits width")

-- ── report ─────────────────────────────────────────────────────────────────
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
