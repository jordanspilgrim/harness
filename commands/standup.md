---
description: Fleet liveness snapshot — who's registered, their status/headline/working-on, unread mail, and staleness — from DLB in one shot.
argument-hint: "[--all]   (add --all to include stale/dead threads)"
allowed-tools: mcp__dlb__list_threads, Bash
---

# /standup — DLB fleet liveness in one command

Give a compact standup of the agent fleet from DLB, so nobody has to ping "any update?" — the
answer is already in `set_status` + `headline` + `working_on`.

## Do this

1. Call `mcp__dlb__list_threads` (v0.5.0+ returns `status`, `status_detail`, `working_on`, `unread_count`,
   `last_seen`, and any recent `headline`). Pass `include_stale: true` when the user included `--all` in
   `$ARGUMENTS`; otherwise show only active threads and give a one-line count of how many stale ones were hidden.
   - If `list_threads` doesn't surface everything you need, you MAY read the store directly (read-only):
     `sqlite3 ~/.dlb/store.sqlite3 "SELECT name, status, status_detail, working_on, datetime(last_seen_ms/1000,'unixepoch','localtime') AS last_seen FROM agents ORDER BY last_seen_ms DESC;"`

2. Render a table sorted by most-recent activity:

   | Thread | Status | Headline / detail | Working on | Unread | Last seen |
   |---|---|---|---|---|---|

   - **Status** uses the DLB convention: `working` / `idle` / `blocked` / `done`. Flag `blocked` rows ⚠️
     and `done` rows ✅.
   - Mark a thread **STALE** if `last_seen` is older than ~30 min (its monitor may be dead / it may have
     exited). Group active rows first, stale rows (if shown) under a "— stale —" divider.

3. Below the table, a 2–3 line summary: how many active / blocked / stale, who holds unread mail, and the
   single most important thing needing attention (a blocker, a dead thread on the critical path, or unread
   mail piling up on a live thread). If any thread is `blocked`, name what it's blocked on from `status_detail`.

## Guardrails
- Read-only. Do NOT send DLB messages, register, or change any thread's state — this is a status view.
- Don't ping threads to ask for updates; report what DLB already knows. If a thread looks dead, say so and
  suggest the owner restart it — don't try to revive it from here.
