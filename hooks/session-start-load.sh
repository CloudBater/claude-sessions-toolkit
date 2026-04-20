#!/usr/bin/env bash
# session-start-load — on SessionStart, if this terminal has no keyed session
# pointer but the repo has an unkeyed one, inherit it: copy unkeyed → keyed
# (so the statusline label is truthful) AND inject the session file's content
# as additionalContext (so what the label says is actually loaded).
#
# Without this hook the statusline would show whatever the previous terminal
# was working on — but the model wouldn't actually have that session in
# context. The label would be lying. This hook makes the label honest.
#
# Opt out by either:
#   - running /save <new-name> (creates a new keyed pointer)
#   - rm <repo>/.local/current-session-<session_id>
#   - clearing the unkeyed pointer (rm <repo>/.local/current-session)
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
