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

### 1.5. Detect Topic Drift — DO NOT overwrite unrelated sessions

**Critical safety check.** If you pick an existing session file to update, verify the current work actually belongs to that session. If the topic has drifted, save as a new session instead.

Drift signals (any one is enough to trigger the check):

1. **Ticket change** — a different ticket ID appears in recent commits, branch name, or the conversation than the ticket recorded in the existing session file
2. **Branch mismatch** — current git branch differs from the existing session's `branch.backend` or `branch.frontend`
3. **Files diverge** — the files you've been touching in this conversation overlap <30% with the session's recorded `files_touched`
4. **Scope mismatch** — the feature you've been working on (judged from recent commits, conversation topics, file paths) doesn't match the session's `scope` line

When any drift signal fires, **STOP and ask the user** before writing:

```
Detected topic drift.

Current saved session:
  Name:   <existing-name>
  Ticket: <existing-ticket>
  Scope:  <existing-scope>
  Files:  <existing-files-summary>

What you've been working on now:
  Ticket: <detected-ticket or "none">
  Branch: <current-branch>
  Scope:  <inferred-scope>
  Files:  <current-files-summary>

These look like different topics. How should I save?

  (a) Save as NEW session — suggested name: <new-name>
      Keeps <existing-name> untouched; creates a separate file.
  (b) Update <existing-name> anyway (if this IS a continuation)
  (c) Skip save
```

Default to **(a)**. Rationale: losing context by merging two topics into one file is much worse than having one extra session file. The user can always delete an extra file; they can't recover a clean session that got polluted by unrelated work.

If the user picks (a):
- Derive a new name using the normal rules from Section 1 but using the CURRENT work's ticket/feature
- Create a fresh session file — do not copy anything from the existing session
- Update `.local/current-session` to the new name
- The previous session file stays exactly as it was

If the user picks (b):
- Proceed to Section 2 with the existing session name
- Be extra careful when merging `done:` lists — label new entries with today's date so the drift is at least visible in the history

Skip the drift check entirely when:
- `$ARGUMENTS` is an explicit session name (user already decided)
- No existing session file matches (nothing to drift from)
- The existing session's `phase` is `done` (completed sessions should never be reopened; force a new session)

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

### 5.5. Write Current-Session Pointers (repo-local + global)

Write the session name to two pointer files:

```bash
echo "<session-name>" > .local/current-session
mkdir -p "$HOME/.claude" && echo "<session-name>" > "$HOME/.claude/current-session"
```

- **`.local/current-session`** — repo-local pointer. Read by `sl` (★ marker), and by the bundled `bin/statusline.sh` when your cwd is inside this repo's tree.
- **`~/.claude/current-session`** — global pointer. Read by `bin/statusline.sh` as a fallback when your cwd is in a sibling repo that has no `.local/current-session` of its own. Lets the active session name follow you across repos.

Every `/save` overwrites both — so the last-saved session is always "current" everywhere. If the user wants to switch active session without saving, they can edit either file manually, or run `/save <name>` on the target session.

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
