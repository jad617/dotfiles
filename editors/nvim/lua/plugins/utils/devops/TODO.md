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
- [ ] **Actionable PR file paths** — jump to a specific file's diff. Deferred: `d` already
      shows all file diffs; per-file jump needs diff-viewer support + line→path mapping.

## 🟢 Performance
- [x] **Section-cache read warmed at idle** — `dashboard.preload_cache` is scheduled from
      init so the file read happens off the first-open path.
- [x] **Request de-dup / race guard** — `load_section` stamps a generation token; stale or
      superseded callbacks (rapid switches, re-loads) are dropped, so no double-render.

## ⚪ Polish / robustness
- [ ] **No automated tests.** Pure helpers (`render.truncate`, markdown `wrap_words` /
      table / `clean`, footer layout) are very testable — several regressions this
      cycle would've been caught.
- [ ] **`:DevOpsHealth`** — extend to check board/sprint access and surface misconfigs.
- [ ] **Inconsistent error surfacing** — standardize `set_message` vs transient `notify`.

## ✅ Done (recent)
- Jira: user filter (`u`, project-scoped) across sections; sprint picker (`v`, incl. past);
  full backlog via Agile endpoint; project-scoped sprint board; My Issues spans projects;
  page size 50→100 (Done tickets); `O` opens board in browser; footer compaction + re-align.
- GitHub: markdown cleanup, bordered activity cards, word-wrap + aligned tables, column
  alignment, Files list + inline review comments.
- Core: char-safe `render.truncate`, cached git call, debounced cache, blockquotes/rules,
  `/`→native search & `S`→DevOps search, sprint-board footer crash fix.
