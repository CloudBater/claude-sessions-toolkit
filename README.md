# claude-sessions

Small toolkit for managing Claude Code sessions on disk, not just in the chat picker.

## Why

Claude Code ships with `/rename` + `/resume`, but they fight you in practice:

- `/rename` stores the name in-session only. Next week you remember "that OAuth thing" but not the exact name — you can't get back without it, and `/resume` now requires a filter (no full list).
- Inevitable outcome: you start a new session with a slightly different name, end up with two similar-looking duplicates, neither holds the full context.
- Chat history is long and unstructured. You don't want to re-read a 200-message transcript to recall what you decided.

## What this gives you

1. **`/save`** — a slash command that writes a curated markdown snapshot (status, decisions, pending, resume hint, timeline) to `.local/sessions/<name>.md`. Updates the file if it already exists. Syncs the `.local/sessions.md` index with disk every time.
2. **`sl`** — a standalone bash/python script that lists every session file sorted by last-updated, with a substring filter. Works as a shell command with no LLM round-trip — pure CLI.
3. **`statusline.sh`** — Claude Code status line that shows the active session name (from `.local/current-session`, written by `/save`, with `~/.claude/current-session` as a cross-repo fallback), plus directory, git branch, and model.

All three share the same session name via `.local/current-session` (repo-local) and `~/.claude/current-session` (global fallback). Save a session and your statusline + `sl` list + chat context all line up — even when you `cd` into a sibling repo. No fighting with Claude Code's built-in `/rename`.

The session files are yours — edit them, grep them, share pieces with teammates. Disk is the source of truth.

## Install

Clone alongside your project, or copy the files in:

```bash
# 1. Copy the save skill into your project's Claude Code commands
cp .claude/commands/save.md /path/to/your/project/.claude/commands/

# 2. Install the sl script (pick one)
# Option A: per-project
cp scripts/sl /path/to/your/project/scripts/
chmod +x /path/to/your/project/scripts/sl
# Run as: !scripts/sl  (prefix with ! in Claude Code to bypass LLM)

# Option B: global
cp scripts/sl ~/bin/sl  # or /usr/local/bin/sl
chmod +x ~/bin/sl
# Run from anywhere: sl

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

Just tell Claude: `resume ENG-123-oauth-login` or `read .local/sessions/ENG-123-oauth-login.md`

Each session file has a `resume_hint` field — Claude reads it and knows exactly what to do next.

## Session file format

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
             ┌──────────────────────────┐
             │ /save ENG-123-oauth      │ ← you run this in Claude Code
             └────────────┬─────────────┘
                          │
       ┌──────────────────┼──────────────────┬───────────────────┐
       ▼                  ▼                  ▼                   ▼
  .local/sessions/    .local/          ~/.claude/         .local/sessions.md
  ENG-123-oauth.md    current-         current-           (index, auto-synced
  (full snapshot)     session          session            with disk)
                      (repo-local)     (global fallback)
                          │                  │
            ┌─────────────┼──────────────────┘
            ▼             ▼
     statusline.sh      sl             future Claude sessions
     ★ ENG-123-oauth    ★ ENG-123      read the snapshot
     (in status bar)    (in list)      to resume
```

Lookup order for the statusline: **repo-local first** (walk up from cwd looking for `.local/current-session`), then **global fallback** (`~/.claude/current-session`). That way the active session name follows you when you `cd` into a sibling repo that doesn't have its own pointer. `sl` stays repo-local — each project sees its own session list.

One command, one source of truth. The statusline + `sl` list + resume path all see the same active session name — no drift.

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
