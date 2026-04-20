Load an existing session into context and switch the active session pointer to it — without overwriting the session file.

## Input

$ARGUMENTS — either a session name (`oauth-login`, `ENG-123-oauth-login`) or the numeric row from `sl` (e.g. `3`). Required.

## Purpose

`/save` is the write path: it updates the session file **and** the pointer. `/read` is the load path: it reads the session file's content into the current conversation's context **and** flips the pointer so the statusline (and `sl`'s ★ marker) reflect the active session.

Primary scenario: you're resuming an older session in this terminal. After `/read`, the prior session's notes are in context and the statusline labels are accurate — without mutating the session file on disk.

## Behavior

### 1. Resolve argument → session name

Locate the sessions directory: walk up from `pwd` looking for `.local/sessions/`. If none is found, print an error and stop.

Then resolve `$ARGUMENTS`:

- **Numeric** (pure digits, e.g. `3`): treat as a 1-based row index into the `sl` listing. Produce the same sort order `sl` uses — parse each `.md` file's YAML frontmatter `updated:` field, falling back to the file's mtime, and sort descending. Pick row N. If N is out of range, print the valid range and stop.
- **Non-numeric**: treat as a session name. Verify `.local/sessions/<arg>.md` exists. If not, list the 3 closest matches (substring) and stop.

Use kebab-case throughout. Never invent a session — `/read` only points at what already exists on disk.

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

### 4. Load the session file into context

Use the `Read` tool against `<repo>/.local/sessions/<name>.md`. This is the whole point of `/read` — the pointer alone doesn't put anything in your context. Skip this step only if the file is empty (size 0).

### 5. Output

Print one short confirmation:

```
Active session → <name> (loaded into context)
  repo-local: <repo>/.local/current-session[-<id>]
  global:     ~/.claude/current-session[-<id>]
```

If session_id was not resolvable, add a note:

```
(session_id unknown — wrote unkeyed pointers only. Your statusline should
 still update; run it once to generate a heartbeat, then rerun /read for
 per-terminal pointer tracking.)
```

## Rules

- Never create a new session file. `/read` is read-only against `.local/sessions/`.
- Never overwrite `.local/sessions/<name>.md`. If you need to save work, use `/save` instead.
- Always `Read` the resolved session file in step 4 — pointer-only is the old broken behavior.
- Accept the row number as printed by `sl` (1-based, in the exact same sort order).
- Never mix numeric and name in the same invocation. Pure digits → number. Anything else → name.
