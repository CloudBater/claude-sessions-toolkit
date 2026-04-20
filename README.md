# claude-sessions-toolkit

**A context lifecycle manager for Claude Code**, built on disk files instead of chat history. Sessions outlive the chat that created them, follow you across repos, and surface their cost on the statusline — so resuming an old topic is one `sl` filter away, not a hunt through the transcript.

## Why `/rename` + `/resume` aren't enough

Claude Code ships with `/rename` (label a chat) and `/resume` (reopen by filter). They look like session management. In practice they manage *the chat window*, not *the unit of work* — and work outlives chats all the time.

A unit of work has a lifecycle: **create → persist → track → switch → resume → retire.** `/rename` + `/resume` cover *name-a-chat* and *reopen-by-name-you-still-remember*. The other four steps are where real sessions die.

| Lifecycle stage | `/rename` + `/resume` | `claude-sessions-toolkit` |
|---|---|---|
| **Capture** state | Transcript *is* the state. Nothing curated. | `/save` writes a structured snapshot: status, phase, done, pending, decisions, resume_hint. |
| **Persist** across chats | Name lives in-chat; dies with the conversation. | `.local/sessions/<name>.md` on disk. Survives restarts, rebuilds, branch switches, new machines. |
| **Discover** past work | `/resume` needs a filter string you still remember; no list, no sort. | `sl` CLI: sorted by `updated`, ★ marks current, filter by name / phase / ticket. No LLM round-trip. |
| **See** current load | Tab title of the chat that set it. | Statusline: `session-name (size)` rendered next to `ctx:N%` — both context-weight signals in one readout. |
| **Switch** topics mid-chat | Silent overwrite of the old session's implicit context. | Drift detection on `/save`; `/read <name\|N>` to flip the pointer without saving. |
| **Follow** across repos / terminals | Bound to one chat in one cwd. | Global pointer fallback; session_id-keyed pointers so two terminals in the same repo don't fight over one pointer. |
| **Resume** cold | Re-read 200 messages. | `resume_hint` is a 2–3 sentence briefing; structured fields brief the next Claude without re-reading chat. |
| **Retire** cleanly | No concept — you just stop using the chat. | `phase: done` locks the session; `/save` forces a new file instead of reopening it. `sd <name\|N>` soft-deletes: archives the file, clears the pointers, reversible via `mv`. |

## What this gives you

Five pieces that share state through pointer files. They can't drift apart — the statusline, `sl` list, `/save`, and `/read` all read/write the same disk state.

1. **`/save`** — Claude Code slash command. Writes or updates `.local/sessions/<name>.md` with frontmatter + appended timeline entry. Detects topic drift. Offers compaction at 40 KB. Refuses to reopen sessions marked `phase: done`. Syncs the `.local/sessions.md` index on every save. Writes the pointer files.

2. **`/read <name|N>`** — Claude Code slash command. *Just* flips the active-session pointer; creates nothing, mutates no session file. Accepts either a name (`/read oauth-login`) or the row number printed by `sl` (`/read 3`). Use it when you've resumed a session in a new terminal and the statusline hasn't caught up, or when you want to switch focus mid-chat without forcing a save.

3. **`sl`** — standalone Python CLI for listing sessions. Sorted by `updated` with phase, size, `status` one-liner, and `★` on any currently-active session. Walks up from cwd, so a single install works from any project subdirectory. The leftmost column is the stable index consumed by both `sr N` (bash) and `/read N` (slash).

4. **`sr`** — standalone Python CLI, bash counterpart of `/read`. Writes the pointer files (all four, session_id-keyed when invoked from inside Claude Code). Accepts `sr <name>`, `sr <N>` from `sl`'s order, or `sr <substring>` (single-match only). No args prints the current pointer.

5. **`sd`** — standalone Python CLI. Soft-deletes a session: moves the `.md` into `.local/sessions/archive/` and clears any pointer file (keyed or unkeyed, repo-local or global) that still references it. Same arg forms as `sr`. Fully reversible — `mv` the archived file back to restore. Completes the session CRUD: `/save` creates, `sl`/`sr` read, `/save` again updates, `sd` drops.

6. **`statusline.sh`** — Claude Code status line (bash). Renders `cwd · branch · model · session-name (size) · ctx:N%`. Session file size sits immediately before live context usage so you read both as one "how much are we carrying" signal. Disk-only lookup (ignores `/rename`). Also writes a per-instance heartbeat (`~/.claude/runtime/instance-<session_id>.json`) so `/save`, `/read`, and `sr` can figure out which Claude terminal they're running in.

**Pointer files.** Two terminals in the same repo working on different sessions would collide on a single pointer — so pointers are keyed by Claude's `session_id` when available, with unkeyed versions as a shared fallback:

- `.local/current-session-<session_id>` — repo-local, per-terminal. Read first by the statusline; no cross-terminal collision.
- `.local/current-session` — repo-local, shared. Read by `sl` for ★ marking, and by the statusline as a fallback when no keyed pointer exists.
- `~/.claude/current-session-<session_id>` — global, per-terminal. For cross-repo work.
- `~/.claude/current-session` — global, shared. Last-resort fallback when cwd is in a repo with no `.local/` of its own.

Every `/save`, `/read`, and `sr` writes all applicable pointers. The session `.md` files are the source of truth; pointers and the index are conveniences — if they drift, rerun `/save` or `/read`/`sr`.

## Install

Clone alongside your project, or copy the files in:

```bash
# 1. Copy the slash commands into your project's Claude Code commands
cp .claude/commands/save.md /path/to/your/project/.claude/commands/
cp .claude/commands/read.md /path/to/your/project/.claude/commands/

# 2. Install the sl + sr + sd scripts (pick one)
# Option A: per-project
cp scripts/sl scripts/sr scripts/sd /path/to/your/project/scripts/
chmod +x /path/to/your/project/scripts/{sl,sr,sd}
# Run as: !scripts/sl, !scripts/sr, !scripts/sd  (prefix with ! in Claude Code to bypass LLM)

# Option B: global
cp scripts/sl scripts/sr scripts/sd ~/bin/  # or /usr/local/bin/
chmod +x ~/bin/sl ~/bin/sr ~/bin/sd
# Run from anywhere: sl, sr, sd

# 3. Install the statusline (optional)
cp bin/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
# Add to ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "bash ~/.claude/statusline.sh"
#   }
```

Add `.local/` to your `.gitignore` so session files stay local.

## Usage

### Save a session

In Claude Code, after doing work:

```
/save
```

Claude will:
1. Derive a session name (from ticket number in commits/branch, or feature name)
2. Gather context (branches, status, what was done, pending items, decisions, lessons)
3. Write `.local/sessions/<name>.md`
4. Sync `.local/sessions.md` index with disk (remove dead entries, add new ones)

Override the name if needed:

```
/save my-custom-name
```

### List sessions

Shell (outside Claude Code — fast, no LLM):

```
sl              # full list
sl oauth        # filter by substring (name, phase, or status)
sl ENG-123      # filter by ticket
```

Example output:

```
 #  UPDATED     PHASE           SESSION                   SIZE  STATUS
 1  2026-01-20  implementing    ENG-145-payment-webhook   9.4K  Webhook signature verification done, retry logic TODO
 2  2026-01-19  deploying       ENG-167-migration-script   16K  Staging cutover verified, prod cutover scheduled
 3  2026-01-19  awaiting-merge  ENG-123-oauth-login        31K  PR open at abc1234, 9 files / +607 lines, tests green
 4  2026-01-18  done            cache-layer-redis          21K  Shipped, dashboards clean for 48h
```

### Resume a session

Tell Claude: `resume ENG-123-oauth-login` or `read .local/sessions/ENG-123-oauth-login.md`. Each session file has a `resume_hint` field — Claude reads it and knows exactly what to do next.

Then flip the pointer so the statusline catches up:

```
# From inside Claude Code (slash command)
/read ENG-123-oauth-login
/read 3                     # row number from `sl` (faster)

# From the shell (bash CLI)
sr ENG-123-oauth-login
sr 3
```

`/read` and `sr` are the pointer-only counterparts to `/save` — they write the active-session pointer files without touching the session `.md`. Handy when you resume in one terminal while another terminal is still on a different session. The bash `sr` is disk-only (no LLM round-trip) and is what you'd wire into shell aliases or scripts; the slash `/read` is what you use mid-conversation without switching surfaces.

### Drop a session

```
sd ENG-123-oauth-login   # archive by name
sd 3                     # archive row N from `sl`
sd                       # show archive location + count
```

`sd` moves the `.md` file into `.local/sessions/archive/` and clears any pointer file (any terminal, any repo) that was still pointing at it. Next `sl` / statusline render will no longer see it. Restore with a plain `mv` — `sd` prints the exact command. The session CRUD rounds out like this:

| Op | Slash (in chat) | Bash (in terminal) | Writes | Needs LLM |
|---|---|---|---|---|
| Create / Update | `/save` | — | snapshot + index + pointers | yes |
| Read (list) | — | `sl` | nothing | no |
| Read (switch active) | `/read` | `sr` | pointers only | no |
| Delete (archive) | — | `sd` | moves file + clears pointers | no |

## Session file format

See [examples/example-session.md](examples/example-session.md) for a complete, realistic example (fictional `ENG-123` OAuth login ticket). The skeleton is:

```markdown
---
name: ENG-123-oauth-login
ticket: ENG-123
started: 2026-01-10
updated: 2026-01-19
branch:
  backend: feature/ENG-123-oauth-login
  frontend: feature/ENG-124-oauth-frontend
scope: OAuth login endpoint for Google / Microsoft / GitHub
phase: awaiting-merge
status: One-line summary of current state, surfaces in `sl` output
done:
  - Specific completed items, most recent first
pending:
  - Remaining work with enough detail to resume cold
blockers: []
key_decisions:
  - Important decisions with the reasoning
files_touched:
  - Key files modified
lessons_learned:
  - Gotchas, bugs found, patterns discovered
resume_hint: |
  2-3 sentences telling future-you exactly what to do next.
  Include exact commands or file paths.
---

## Timeline

### 2026-01-19

- What was accomplished today
- Key decisions
- What's next
```

## How the pieces fit

```
   /save ENG-123-oauth            /read 3   (slash, in chat)
                                   sr 3      (bash, in terminal)
       │                                    │
       │   writes snapshot +                │   writes pointers only
       │   index + pointers                 │
       ▼                                    ▼
  .local/sessions/ENG-123-oauth.md    .local/current-session            ──► sl ★
  .local/sessions.md  (index)          .local/current-session-<sid>     ──► statusline
                                       ~/.claude/current-session        ──► statusline (cross-repo)
                                       ~/.claude/current-session-<sid>  ──► statusline (per-terminal)
       ▲
       │
   future Claude sessions read the snapshot to resume

  statusline.sh also writes ~/.claude/runtime/instance-<sid>.json every render
  — that's how /save, /read, and sr discover which terminal they're in.
```

**Statusline lookup order** (first hit wins):

1. `<repo>/.local/current-session-<session_id>` — per-terminal, repo-local
2. `<repo>/.local/current-session` — shared, repo-local
3. `~/.claude/current-session-<session_id>` — per-terminal, global
4. `~/.claude/current-session` — shared, global fallback

When the pointer is found via walk-up, the statusline also locates the session's `.md` file in the same `.local/sessions/` dir and prints its on-disk size — e.g. `ENG-123-oauth-login (9.7K) ctx:42%`. Pairing file size with live context usage makes both "how much context is this costing" signals scannable as one unit. Global-fallback hits skip the size since the owning repo is unknown.

**Why session_id keying.** Claude Code runs one process per terminal, each with a unique `session_id` in the JSON it pipes to statuslines. The statusline uses that to write a heartbeat file (`~/.claude/runtime/instance-<session_id>.json` = current cwd). When `/save` or `/read` runs, it scans that directory to figure out which `session_id` is *this terminal* (most-recent heartbeat whose cwd matches ours), then writes session_id-keyed pointers. Two terminals in the same repo now track different sessions without stomping on each other.

`sl` stays repo-local by design — each project sees its own session list. Four surfaces (`/save`, `/read`, `sl`, statusline), one disk state they all agree on.

## Topic drift protection

A common failure mode: you were working on session A this morning, then without thinking you start on a different task B this afternoon. If `/save` just blindly updated A's file with B's context, you'd lose a clean A snapshot and end up with a confusing A+B hybrid.

`/save` detects drift by comparing:

- Ticket ID (from commits, branch name, conversation)
- Current git branch vs session's recorded branch
- Files you've touched vs session's recorded files
- Feature/scope inferred from conversation

If drift is detected, it stops and asks:

```
Detected topic drift.

Current saved session: ENG-123-oauth-login (scope: OAuth login endpoint)
What you've been working on: ENG-145-payment-webhook (scope: Stripe webhook handler)

These look like different topics. How should I save?
  (a) Save as NEW session — suggested name: ENG-145-payment-webhook
  (b) Update ENG-123 anyway (if this IS a continuation)
  (c) Skip save
```

The default is (a) — save as new. Keeping a clean A is more valuable than preventing an extra file.

## Tips

- **One session per topic** — don't mix work across topics in one file
- **Compact when files grow past 40 KB** — the `/save` skill asks automatically
- **`resume_hint` is the money field** — write it like you're briefing a new teammate
- **Timeline is append-only** — never delete history; compact old entries into weekly summaries instead
- **Disk over memory** — the index is a convenience; the files are truth
- **Trust the drift check** — when `/save` asks if you're starting a new topic, err on the side of "yes, new session"

## License

MIT
