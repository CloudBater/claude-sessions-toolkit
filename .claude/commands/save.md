Save or update session context so future conversations can resume seamlessly.

## Input

$ARGUMENTS — optional session name override (e.g., `oauth-login`, `ENG-123-oauth`). If omitted, auto-detect from context.

## Behavior

### 1. Detect Session Name

Determine the session name using this priority:

1. **Explicit argument** — if `$ARGUMENTS` is provided and non-empty, use it as the session name
2. **Existing session file** — scan `.local/sessions/` for a file whose content matches the current working context (same ticket, same branch, same feature area). If found, update that file
3. **Auto-derive from context** — build the name from available signals:
   - If a ticket number is visible in recent commits, branch name, or conversation (e.g. `ENG-123`, `PROJ-45`, `#456`): use `<ticket>-short-title` (e.g., `ENG-123-oauth-login`)
   - If no ticket but a clear feature name exists: use kebab-case feature name (e.g., `oauth-login`, `sso-auth`)
   - Last resort: use `session-YYYY-MM-DD` with today's date

### 2. Gather Context

Collect the following from the current conversation and repo state:

```yaml
name: <session-name>
ticket: <ticket-id or null>
started: <date first seen or today>
updated: <today>
branch:
  backend: <current BE branch, if applicable>
  frontend: <current FE branch, if applicable>
scope: <brief — which apps/features are touched>
phase: <current phase — planning | implementing | testing | deploying | done>
status: <one-line summary of where things stand — surfaces in `sl` output>
done:
  - <completed items, most recent first>
pending:
  - <remaining items>
blockers:
  - <blockers if any, otherwise omit>
key_decisions:
  - <important decisions made during this session>
files_touched:
  - <key files modified, grouped if helpful>
lessons_learned:
  - <gotchas, bugs found, patterns discovered>
resume_hint: |
  <2-3 sentences telling a future session exactly what to do next.
   Include exact commands or file paths when possible.>
```

### 3. Write or Update

- **Directory**: `.local/sessions/`
- **Filename**: `<session-name>.md` (kebab-case)
- **Format**: YAML frontmatter between `---` fences, followed by a `## Timeline` section with date-stamped entries

If the file already exists:
- Update the frontmatter fields (updated, branch, phase, status, done, pending, etc.)
- **Append** a new timeline entry — never delete previous entries
- Merge `done` lists (don't duplicate)

If the file is new:
- Create it with all fields populated
- Add the first timeline entry

### 4. Timeline Entry Format

```markdown
## Timeline

### YYYY-MM-DD

- <what was accomplished today>
- <key changes or decisions>
- <what's next>
```

### 4.5. Check Size — Ask Before Bloat

After writing the session file, check its size:

```bash
wc -c .local/sessions/<name>.md
```

If the file exceeds **40 KB**, ask the user if they want to compact it. Compacting workflow:

- **Preserve verbatim**: latest `resume_hint`, latest `status`, `key_decisions`, `lessons_learned`, last 1-2 timeline entries
- **Compact**: collapse older daily timeline entries into weekly/phase summaries; trim `done:` list to recent milestones (move older ones into timeline summaries); dedupe `files_touched:` if it appears in every timeline entry; trim verbose status to 2-3 sentences
- **Reduce obsolete context**: when a major pivot happens (e.g. POC abandoned, approach changed), compress the obsolete approach into a short "archived" section and expand the current approach
- **Target**: 15-25 KB

Typical session files are 5-30 KB. 40 KB+ usually means timeline bloat or unreduced pivot history.

### 5. Sync Sessions Index with Disk

**Disk is the source of truth** — the index must always reflect what exists in `.local/sessions/`.

Sync workflow:

1. **List disk contents**: `ls .local/sessions/*.md` — this is the authoritative set
2. **Parse existing index** (`.local/sessions.md`, if it exists): extract session names from `## Saved Sessions` entries (pattern `[<name>](sessions/<name>.md)`)
3. **Reconcile**:
   - **Add** any on-disk file that's not in the index (pull the one-liner from the file's `status:` frontmatter field, truncated to ~200 chars)
   - **Remove** any index entry whose file doesn't exist on disk
   - **Update** the current session's entry with the latest `status:` line
4. **Preserve** any multi-terminal active-session blocks at the top of `sessions.md` — only reconcile the `## Saved Sessions` list at the bottom
5. If multiple `## Saved Sessions` headers exist (legacy duplication), consolidate into one sorted list

Always run this full sync step during `/save`, not just when adding the current session. This prevents the index from accumulating dead links when the user deletes session files manually.

### 5.5. Write Current-Session Pointer

Write the session name to `.local/current-session` (one line, no trailing newline is fine):

```bash
echo "<session-name>" > .local/current-session
```

This pointer is read by the bundled `bin/statusline.sh` so the Claude Code status line shows the active session name. Every `/save` overwrites it — so the last-saved session is always the "current" one from the statusline's perspective.

If the user wants to switch active session without saving (e.g. to show a different session in the statusline), they can either run `/save <name>` on the target session or edit `.local/current-session` manually.

### 6. Output

After saving, print:

```
Saved: .local/sessions/<name>.md
Phase: <phase>
Next: <resume_hint summary>
```

## Rules

- Always use kebab-case for filenames
- Ticket numbers go first in the name: `ENG-123-oauth-login` not `oauth-login-ENG-123`
- Don't save secrets, credentials, or tokens
- Don't duplicate what's already in spec/design files — reference them instead (e.g., "see docs/oauth-design.md")
- Keep `resume_hint` actionable — it should tell the next session exactly what command to run or what file to open
- The session file is a living document — each `/save` adds to it, never replaces history
