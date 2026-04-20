Switch the active session pointer to an existing session — without saving content.

## Input

$ARGUMENTS — either a session name (`oauth-login`, `ENG-123-oauth-login`) or the numeric row from `sl` (e.g. `3`). Required.

## Purpose

`/save` is the write path: it updates the session file **and** the pointer. `/use` is just the pointer. It's what you run when you want the statusline (and `sl`'s ★ marker) to flip to a different session without creating or mutating any session file.

Primary scenario: you just resumed an older session in this terminal. Nothing is being saved yet, but the statusline should already reflect the switch so you don't lose track of which conversation is working on which session.

## Behavior

### 1. Resolve argument → session name

Locate the sessions directory: walk up from `pwd` looking for `.local/sessions/`. If none is found, print an error and stop.

Then resolve `$ARGUMENTS`:

- **Numeric** (pure digits, e.g. `3`): treat as a 1-based row index into the `sl` listing. Produce the same sort order `sl` uses — parse each `.md` file's YAML frontmatter `updated:` field, falling back to the file's mtime, and sort descending. Pick row N. If N is out of range, print the valid range and stop.
- **Non-numeric**: treat as a session name. Verify `.local/sessions/<arg>.md` exists. If not, list the 3 closest matches (substring) and stop.

Use kebab-case throughout. Never invent a session — `/use` only points at what already exists on disk.

### 2. Discover this terminal's session_id

Claude Code does not expose `session_id` as an env var, but the bundled statusline writes a heartbeat to `~/.claude/runtime/instance-<session_id>.json` on every render. That file's content is `{"cwd": "<cwd>", "ts": <unix-ts>}`.

To find the id for THIS terminal:

```bash
ls -t ~/.claude/runtime/instance-*.json 2>/dev/null | while read -r f; do
    cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
    if [ "$cwd" = "<our cwd>" ]; then
        basename "$f" .json | sed 's/^instance-//'
        break
    fi
done
```

The most-recently-modified matching file is the terminal the user just prompted — i.e. us. If no match is found, session_id is unknown; proceed without the keyed pointer writes.

### 3. Write the pointer files

For repo-local (walk up from cwd to find the `.local/` directory):

```bash
echo "<name>" > "<repo>/.local/current-session"
[ -n "<session_id>" ] && echo "<name>" > "<repo>/.local/current-session-<session_id>"
```

For global:

```bash
mkdir -p "$HOME/.claude"
echo "<name>" > "$HOME/.claude/current-session"
[ -n "<session_id>" ] && echo "<name>" > "$HOME/.claude/current-session-<session_id>"
```

Writes:
- `.local/current-session` + `~/.claude/current-session` — unkeyed pointers. `sl` uses the repo-local one for its ★ marker. Kept for backward compat and as a "most recent across terminals" signal.
- `.local/current-session-<session_id>` + `~/.claude/current-session-<session_id>` — keyed pointers. These are what let two terminals in the same repo track different sessions without fighting.

### 4. Output

Print one short confirmation:

```
Active session → <name>
  repo-local: <repo>/.local/current-session[-<id>]
  global:     ~/.claude/current-session[-<id>]
```

If session_id was not resolvable, add a note:

```
(session_id unknown — wrote unkeyed pointers only. Your statusline should
 still update; run it once to generate a heartbeat, then rerun /use for
 per-terminal pointer tracking.)
```

## Rules

- Never create a new session file. `/use` is read-only against `.local/sessions/`.
- Never overwrite `.local/sessions/<name>.md`. If you need to save work, use `/save` instead.
- Accept the row number as printed by `sl` (1-based, in the exact same sort order).
- Never mix numeric and name in the same invocation. Pure digits → number. Anything else → name.
