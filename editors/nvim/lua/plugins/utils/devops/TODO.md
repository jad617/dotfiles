# DevOps plugin — TODO

Backlog of fixes and improvements. Priority: 🔴 bug/correctness · 🟠 Jira UX ·
🟡 GitHub · 🟢 perf · ⚪ polish.

## 🔴 Bugs / correctness
- [x] **Assign picker (`a`) is org-wide + flat** — now uses `project_assignees` (the
      project's teammates) + Me/Unassigned, like the `u` filter.
- [x] **No pagination — large lists silently truncate.** `search` follows `nextPageToken`
      and `board_backlog` follows `startAt`, fetching up to MAX_ISSUES (1000).
      (Epics / JQL backlog fallback still single-page — low impact.)
- [x] **`O` board URL assumes a company-managed project.** Now branches on
      `project.style`: team-managed (next-gen) drops the `/c/` segment.

## 🟠 Jira UX
- [x] **`👤` filter indicator** now only shows on the sections it affects (My Issues /
      Backlog / Epics), not the team Sprint Board.
- [x] **"Back to active sprint"** — the sprint picker now has a "● Active sprint(s)" reset
      at the top.
- [x] **`u` "Search by name…" fallback** — picker has a live, project-scoped search for
      anyone assignable, not just recent assignees.
- [x] **My Issues scope predictable** — always spans projects; only scopes to the project
      on the `s` toggle.
- [x] **`O` opens the full team board on the Sprint Board** (no `?assignee`); personal /
      filtered view on the other sections.
- [x] **Empty filtered list** now reads "(no issues for <user>)".

## 🟡 GitHub
- [~] **Inline review comments hardened** — line fallback (`line`/`original_line`/
      `position`/`original_position`) and author fallback. Still needs a live check of
      the `gh api …/pulls/N/comments` shape.
- [x] **Openable link URLs** — `gx` on a PR collects URLs from body/comments/reviews and
      opens (single) or picks (many).
- [x] **PR changed-files tree** — `f` on a PR opens `ui/pr_files.lua`: a file tree (left
      split, grouped by dir, +/- per file) with live diff preview on the right. Navigate
      j/k/↵, q to close.

## 🟢 Performance
- [x] **Section-cache read warmed at idle** — `dashboard.preload_cache` is scheduled from
      init so the file read happens off the first-open path.
- [x] **Request de-dup / race guard** — `load_section` stamps a generation token; stale or
      superseded callbacks (rapid switches, re-loads) are dropped, so no double-render.

## ⚪ Polish / robustness
- [x] **Test harness** — `tests/run.lua` (run with `luajit tests/run.lua`) stubs `vim`
      and covers `render.truncate`/`pad`/`fit` and `markdown.clean`/`render`
      (headers, bullets, blockquotes, rules, word-wrap, table fit). 23 assertions.
- [x] **`:DevOpsHealth`** now shows the remembered project/board and flags "no board"
      (the cause of an empty Sprint Board).
- [~] **Error surfacing** — kept as-is: `set_message` for section-load errors (shown in
      the content pane) vs `notify` for action results (toasts) is a deliberate split.

## ✅ Done (recent)
- Jira: user filter (`u`, project-scoped) across sections; sprint picker (`v`, incl. past);
  full backlog via Agile endpoint; project-scoped sprint board; My Issues spans projects;
  page size 50→100 (Done tickets); `O` opens board in browser; footer compaction + re-align.
- GitHub: markdown cleanup, bordered activity cards, word-wrap + aligned tables, column
  alignment, Files list + inline review comments.
- Core: char-safe `render.truncate`, cached git call, debounced cache, blockquotes/rules,
  `/`→native search & `S`→DevOps search, sprint-board footer crash fix.
