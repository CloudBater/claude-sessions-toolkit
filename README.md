# claude-sessions

Small toolkit for managing Claude Code sessions on disk, not just in the chat picker.

## Why

Claude Code ships with `/rename` + `/resume`, but they fight you in practice:

- `/rename` stores the name in-session only. Next week you remember "that OAuth thing" but not `LT-3066-oauth-direct-login` — you can't get back without the exact name, and `/resume` now requires a filter (no full list).
- Inevitable outcome: you start a new session with a slightly different name, end up with two similar-looking duplicates, neither holds the full context.
- Chat history is long and unstructured. You don't want to re-read a 200-message transcript to recall what you decided.

## What this gives you

1. **`/save`** — a slash command that writes a curated markdown snapshot (status, decisions, pending, resume hint, timeline) to `.local/sessions/<name>.md`. Updates the file if it already exists. Syncs the `.local/sessions.md` index with disk every time.
2. **`sl`** — a standalone bash/python script that lists every session file sorted by last-updated, with a substring filter. Works as a shell command with no LLM round-trip — pure CLI.

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
sl LT-3066      # filter by ticket
```

Example output:

```
 #  UPDATED     PHASE           SESSION                       SIZE  STATUS
 1  2026-04-17  implementing    LT-3089-dev-api-primary       9.4K  BE PR #1072 open vs develop (3 commits)...
 2  2026-04-17  deploying       LT-3082-mcp-onboarding-page    16K  BE v1.14.0.2 hotfix verified on staging...
 3  2026-04-17  awaiting-merge  LT-3066-oauth-direct-login     31K  BE PR #1071 at 7a0efcc2, 9 files / +607...
 4  2026-04-16  sentry-cloud    LT-3079-sentry-setup           21K  Sandbox BE + FE wired to Sentry Cloud...
```

### Resume a session

Just tell Claude: `resume LT-3066-oauth-direct-login` or `read .local/sessions/LT-3066-oauth-direct-login.md`

Each session file has a `resume_hint` field — Claude reads it and knows exactly what to do next.

## Session file format

```markdown
---
name: LT-3066-oauth-direct-login
ticket: LT-3066
started: 2026-03-20
updated: 2026-04-17
branch:
  backend: feature/LT-3066-oauth-direct-login
  frontend: feature/LT-3054-sso-frontend
scope: OAuth direct login endpoint for 3 providers
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

### 2026-04-17

- What was accomplished today
- Key decisions
- What's next
```

## Tips

- **One session per topic** — don't mix work across topics in one file
- **Compact when files grow past 40 KB** — the `/save` skill asks automatically
- **`resume_hint` is the money field** — write it like you're briefing a new teammate
- **Timeline is append-only** — never delete history; compact old entries into weekly summaries instead
- **Disk over memory** — the index is a convenience; the files are truth

## License

MIT
