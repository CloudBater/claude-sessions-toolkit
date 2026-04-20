Save a tight session snapshot so a future conversation can resume.

## Input

$ARGUMENTS — optional session name. If omitted, auto-detect.

## Behavior

### 1. Pick the session name

In order:

1. **Explicit `$ARGUMENTS`** — use as-is (kebab-case).
2. **Existing file matches current work** — same ticket, branch, or feature → update it.
3. **Derive** — `<ticket>-short-slug` if a ticket is visible; else kebab-case feature; last resort `session-YYYY-MM-DD`.

### 2. Drift check (only when updating an existing file)

If the existing file's ticket/branch/scope clearly doesn't match the current work, **stop and ask**:

```
Topic drift suspected.
  Existing: <name> (<ticket>, <scope>)
  Current:  <detected ticket / branch / scope>

(a) Save as NEW session: <suggested-new-name>
(b) Update <existing-name> anyway
(c) Skip
```

Default (a). Skip the check when `$ARGUMENTS` is given, no existing file matches, or the existing session's `phase` is `done`.

### 3. Write or update — lite by default

**Required frontmatter:**

```yaml
name: <kebab-case>
updated: <today YYYY-MM-DD>
phase: planning | implementing | testing | deploying | done
status: <one line, ≤200 chars — surfaces in `sl`>
resume_hint: |
  <≤5 lines: exact next command/file to open, plus 1-2 lines of context>
```

**Optional — include only if non-trivial and novel:**

```yaml
ticket: <id>
branch: { backend: <b>, frontend: <b> }   # only if relevant
scope: <one phrase>
done: [<recent items, ≤5>]
pending: [<remaining items, ≤5>]
blockers: [<if any>]
key_decisions: [<≤3, each ≤1 line>]
lessons_learned: [<≤3, each ≤1 line — only genuinely new lessons>]
files_touched: [<key files, ≤8>]
```

Skip an optional section if it has nothing new to say. **Don't pad.**

### 4. Timeline — one entry per save

Append (never replace) under `## Timeline`:

```markdown
### YYYY-MM-DD

- <≤5 bullets, ≤1 line each: what changed, decisions, next step>
```

### 5. Update-only path (existing file)

When updating, **change only what changed**:

- Refresh `updated`, `status`, `phase`, `resume_hint`.
- Append a new timeline entry.
- Add to `done` / `key_decisions` / `lessons_learned` only if you have new items. Don't rewrite existing items.
- Never delete prior timeline entries.

This keeps the diff small and the file growing slowly.

### 6. Size target

Aim for **15-25 KB total**. If you're approaching 30 KB, compact older timeline entries into a one-line phase summary before adding today's entry.

### 7. Sync `.local/sessions.md` index

Disk is the source of truth.

1. List `.local/sessions/*.md`.
2. In `.local/sessions.md`, reconcile the `## Saved Sessions` block: add missing files (one-liner from frontmatter `status:`, ≤200 chars), remove dead links, refresh the current session's line.
3. Preserve any active-session blocks above `## Saved Sessions` — only touch that one list.

### 8. Write the pointer files

Discover this terminal's `session_id` from the statusline heartbeat:

```bash
session_id=""
if compgen -G "$HOME/.claude/runtime/instance-*.json" >/dev/null 2>&1; then
  session_id="$(ls -t "$HOME/.claude/runtime/"instance-*.json | while read -r f; do
    [ "$(jq -r '.cwd // empty' "$f" 2>/dev/null)" = "$(pwd)" ] && \
      basename "$f" .json | sed 's/^instance-//' && break
  done)"
fi
```

Write four pointers (skip the keyed pair if `session_id` is empty):

```bash
echo "<name>" > .local/current-session
echo "<name>" > "$HOME/.claude/current-session"
[ -n "$session_id" ] && echo "<name>" > ".local/current-session-$session_id"
[ -n "$session_id" ] && echo "<name>" > "$HOME/.claude/current-session-$session_id"
```

Pointer roles:
- **Keyed** (`current-session-<sid>`) — THIS terminal's active session. Read by the statusline to render the label.
- **Unkeyed** (`current-session`) — most-recent-across-terminals. Read by `sl` for its ★ marker. **Not** consulted by the statusline.

### 9. Output

```
Saved: .local/sessions/<name>.md (<size>)
Phase: <phase>
Next:  <one-line resume_hint summary>
```

## Rules

- kebab-case filenames; ticket goes first (`ENG-123-oauth-login`, not `oauth-login-ENG-123`).
- No secrets, tokens, or credentials.
- Reference spec/design files; don't duplicate them.
- `resume_hint` is the most important field — make it actionable (a command, a file path, or a 1-sentence next step).
- Be terse. A future session will read this; brevity is respect for that future context budget.
