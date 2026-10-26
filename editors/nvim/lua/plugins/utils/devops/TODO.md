# DevOps plugin — TODO

Backlog of fixes and improvements. Priority: 🔴 bug/correctness · 🟠 Jira UX ·
🟡 GitHub · 🟢 perf · ⚪ polish.

## 🔴 Bugs / correctness
- [x] **Assign picker (`a`) is org-wide + flat** — now uses `project_assignees` (the
      project's teammates) + Me/Unassigned, like the `u` filter.
- [x] **No pagination — large lists silently truncate.** `search` follows `nextPageToken`
      and `board_backlog` follows `startAt`, fetching up to MAX_ISSUES (1000).
      Epics and the JQL backlog fallback page too (shared `search_all`).
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
- [x] **`>` / `<` quick advance** to the next / previous board column.
- [x] **No-board warning** on My Issues (no board, or columns failed to load).

## 🟡 GitHub
- [~] **Inline review comments hardened** — line fallback (`line`/`original_line`/
      `position`/`original_position`) and author fallback. Still needs a live check of
      the `gh api …/pulls/N/comments` shape.
- [x] **Openable link URLs** — `gx` on a PR collects URLs from body/comments/reviews and
      opens (single) or picks (many).
- [x] **PR changed-files tree in the diff viewer** — a left tree pane (grouped by dir) is
      shown by default inside `d`; j/k live-jumps the diff to that file, ↵ focuses the
      diff, `f` toggles the pane. Works in both unified and split modes.
- [x] **Review threads inline in the diff** — threads render under their line (split:
      commented side, padded opposite); `]c`/`[c` jump (also from the tree), `r` replies.
- [x] **Merge readiness** — Review field shows approvals vs required, your verdict, and
      pending code owners (branch protection via GraphQL).
- [x] **Re-review flag + `U`** — Reviews list marks PRs with new commits since your
      approval; `U` diffs only what changed since your last verdict.
- [x] **Comment drafts** — cancelled comments are kept in `drafts.json` and restored.
- [x] **Jira ↔ PR links** — keys from PR branch/title/body; `↵` on a linked row opens it,
      `BS` goes back.
- [x] **Paged diff viewer** — one file per page (other files folded away). Each pane title
      shows the file path · side, and a new or deleted file shows a "∅" placeholder on
      the empty pane. An END/TOP banner marks the edge of each file and is pinned to the
      bottom on short files. At the edge, the first scroll stops; `ui.diff_overscroll`
      more scrolls (default 2) flip to the next or previous file. `gg`/`G` stay inside the
      file and `]f`/`[f` jump between files. Diff buffers (`ft=devops_diff`) are exempt
      from scrollEOF and `scrolloffpad`.
- [x] **Viewed checkmarks** — `x` in a PR diff toggles GitHub's "Viewed" state for the
      page's file (or the tree row) and moves on to the next unviewed file. The tree shows
      a ✓ and dims viewed files, with a count in its header, and the pane title gets a ✓.
      `]f`/`[f` skip viewed files unless every other file is viewed.
- [x] **Suggestion blocks** — `s` (normal or visual) on the new side opens a comment
      prefilled with a ```` ```suggestion ```` block; multi-line comments send
      `start_line`. Submitting (`S`) previews the pending comments.
- [x] **Search across files** — `/ ? n N` in the paged diff jump to matches in other files.
- [x] **CI job logs** — `↵` on a check in the PR Checks tab opens its Actions log (failed
      steps first, full log as fallback). Laid out like GitHub: a summary line, one header
      bar per step (✓/✗, line count, duration) recovered from the runner's `##[group]Run`
      markers, failed steps open and the rest folded, nested groups folded, per-step line
      numbers, tinted error/warning lines (incl. compiler `error:` lines), `$` commands,
      token colors (paths, URLs, strings, numbers, `$VARS`, shell keywords in the step script,
      `key:` labels, error/warning/note/pass words), and
      shortened runner paths. Keys: `]e`/`[e` errors, `]s`/`[s` steps, `↵`/`Tab` fold,
      `w` wrap, `o` browser.
- [x] **Review-request watch** — polls `review-requested:@me` every
      `github.poll_interval` seconds (default 120, 0 = off), notifies on new requests and
      badges the Reviews sidebar row with `● N` until the section is opened.
- [x] **Branch from a ticket** — `B` checks out a branch named by `jira.branch_format`
      (default `feature/{key}-{slug}`) and moves a "To Do" ticket to In Progress.
- [x] **Create flow** — `+` asks project → type → epic → sprint → summary (defaults to the
      current git branch) → description.

## ⚪ Polish
- [x] **Error float** — failures open a red float instead of a fleeting notify.
- [x] **`NVIM_READONLY_STATE=1`** — test runs never write state/drafts/workspaces.
- [x] **Theming** — all `DevOps*` groups live in `ui/theme.lua`, set with `default = true`
      so colorschemes/users can override; `ui = { theme = "auto" }` follows the colorscheme,
      `ui.highlights` overrides any group, `ui.issue_types` / `ui.status_icons` set icons.
- [x] **Visual polish** — status/state pills in headers, chips for labels/components/fix
      versions, type-coloured issue icons, priority icons, status icons in list rows.
- [x] **Detail tabs** — `Tab`/`S-Tab` cycle Overview · Comments · Pull requests (Jira) and
      Overview · Conversation · Checks · Files (PRs); list `c` opens on Comments.
      `ui.detail_tabs = false` restores the single scroll.

## 🟢 Performance
- [x] **Section-cache read warmed at idle** — `dashboard.preload_cache` is scheduled from
      init so the file read happens off the first-open path.
- [x] **Request de-dup / race guard** — `load_section` stamps a generation token; stale or
      superseded callbacks (rapid switches, re-loads) are dropped, so no double-render.

## ⚪ Polish / robustness
- [x] **Test harness** — `tests/run.lua` (run with `luajit tests/run.lua`) stubs `vim`
      and covers `render.truncate`/`pad`/`fit` and `markdown.clean`/`render`
      (headers, bullets, blockquotes, rules, word-wrap, table fit). 23 assertions.
- [x] **Headless spec** — `tests/nvim_spec.lua` (run with `nvim --headless --clean -l
      tests/nvim_spec.lua`) stubs the Jira HTTP client and covers sprint paging, the
      project-sprint filter/cache, epic children paging, the parent link, the child-issues
      panel and its `F` filter.
- [x] **Detail vs list races** — a list fetch can't overwrite an open/loading ticket, and
      only the newest ticket load renders.
- [x] **`:DevOpsHealth`** checks Jira auth and project access, `gh` login and token
      scopes, curl and git; it also shows the remembered project/board and flags "no board"
      (the cause of an empty Sprint Board).
- [~] **Error surfacing** — kept as-is: `set_message` for section-load errors (shown in
      the content pane) vs `notify` for action results (toasts) is a deliberate split.

## ✅ Done (recent)
- [x] **Compact footer + grouped help**: one-line footer with the 5–7 keys for the current view and `? all keys`; `?` opens a per-context help float (Navigate / Actions / Filters / Log viewer / Window / Badges), both driven by one key table.
- Jira: user filter (`u`, project-scoped) across sections; sprint picker (`v`, incl. past);
  full backlog via Agile endpoint; project-scoped sprint board; My Issues spans projects;
  page size 50→100 (Done tickets); `O` opens board in browser; footer compaction + re-align.
- GitHub: markdown cleanup, bordered activity cards, word-wrap + aligned tables, column
  alignment, Files list + inline review comments.
- Core: char-safe `render.truncate`, cached git call, debounced cache, blockquotes/rules,
  `/`→native search & `S`→DevOps search, sprint-board footer crash fix.
