#!/usr/bin/env bash
# session-start-load — branches on SessionStart `source`:
#
#   startup  → inherit from sibling terminal (cross-terminal continuity).
#              If this terminal has no keyed pointer but the repo has an
#              unkeyed one, copy unkeyed → keyed AND inject the session
#              file as additionalContext so the statusline label and the
#              model's context agree.
#
#   clear    → user explicitly asked for a fresh start. /clear issues a
#              new session_id, so a no-op would let the statusline fall
#              back to the unkeyed pointer and lie. Write an EMPTY keyed
#              pointer (statusline reads "" and hides the label) and exit.
#
#   resume   → conversation already carries its prior context. Don't
#   compact    re-inject. Skip silently.
#
# Without this hook the statusline would show whatever the previous terminal
# was working on — but the model wouldn't actually have that session in
# context. The label would be lying. This hook makes the label honest.
#
# Opt out of inherit on startup: /save <new-name>, /clear, or rm of the
# keyed pointer at <repo>/.local/current-session-<session_id>.
#
# Wire up by adding to .claude/settings.json:
#
#   "hooks": {
#     "SessionStart": [
#       {
#         "hooks": [
#           {
#             "type": "command",
#             "command": "\"$CLAUDE_PROJECT_DIR\"/hooks/session-start-load.sh"
#           }
#         ],
#         "matcher": ""
#       }
#     ]
#   }

set -euo pipefail

INPUT=$(cat)

session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
cwd=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
src=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)
[ -z "$cwd" ] && cwd="$PWD"

# Walk up from cwd to find the repo root containing .local/sessions/.
repo=""
dir="$cwd"
while [ "$dir" != "/" ] && [ -n "$dir" ]; do
  if [ -d "$dir/.local/sessions" ] || [ -f "$dir/.local/current-session" ]; then
    repo="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
[ -z "$repo" ] && exit 0

# /clear: explicit fresh start. Empty keyed pointer wins the statusline
# lookup over the unkeyed fallback, blanking the label.
if [ "$src" = "clear" ] && [ -n "$session_id" ]; then
  : > "$repo/.local/current-session-$session_id" 2>/dev/null || true
  mkdir -p "$HOME/.claude" 2>/dev/null || true
  : > "$HOME/.claude/current-session-$session_id" 2>/dev/null || true
  exit 0
fi

# Inherit only on a truly fresh terminal. resume/compact already have
# their context — re-injecting would duplicate it.
if [ -n "$src" ] && [ "$src" != "startup" ]; then
  exit 0
fi

# If this terminal already owns a keyed pointer, do nothing.
if [ -n "$session_id" ] && [ -f "$repo/.local/current-session-$session_id" ]; then
  exit 0
fi

# Need an unkeyed pointer to inherit from.
[ -f "$repo/.local/current-session" ] || exit 0

name=$(head -n1 "$repo/.local/current-session" | tr -d '\n\r')
[ -z "$name" ] && exit 0

session_file="$repo/.local/sessions/$name.md"
[ -f "$session_file" ] || exit 0

# Copy unkeyed → keyed so the statusline reflects this terminal honestly.
if [ -n "$session_id" ]; then
  printf '%s\n' "$name" > "$repo/.local/current-session-$session_id" 2>/dev/null || true
  mkdir -p "$HOME/.claude" 2>/dev/null || true
  printf '%s\n' "$name" > "$HOME/.claude/current-session-$session_id" 2>/dev/null || true
fi

# Build the additionalContext payload. Keep it framed so Claude knows where
# this came from and can decide how heavily to lean on it.
content=$(cat "$session_file")
header="Inherited session: \`$name\` (auto-loaded from \`$session_file\` because this terminal had no keyed session pointer). To start a fresh session, run \`/save <new-name>\` or \`/clear\`."
additional=$(printf '%s\n\n---\n\n%s' "$header" "$content")

jq -n --arg ctx "$additional" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
