#!/usr/bin/env bash
# Claude Code status line — shows the current saved session name.
#
# Two jobs:
#   1. Resolve + render the active session name (and its file size) alongside
#      cwd, branch, model, and ctx%.
#   2. Write a per-Claude-instance heartbeat to ~/.claude/runtime/ so that the
#      /save and /read slash commands can discover their own session_id (which
#      Claude Code does not expose as an env var).
#
# Resolution priority for the current session name (first match wins):
#   1. <repo>/.local/current-session-<session_id>   (keyed, repo-local)
#   2. ~/.claude/current-session-<session_id>       (keyed, global)
#
# THIS terminal's label only — no fallback to the unkeyed shared pointer.
# A new Claude Code session starts blank; the user must `/read <name>` to
# load a saved session into this terminal. This avoids the silent "label
# says X but the model never loaded X" failure mode.
#
# The unkeyed pointers (.local/current-session, ~/.claude/current-session)
# are still written by /save and read by `sl` for its ★ marker — they
# represent "most recent across terminals" but are deliberately NOT used
# for per-terminal label rendering.
#
# Usage (in ~/.claude/settings.json):
#   "statusLine": { "type": "command", "command": "bash /path/to/bin/statusline.sh" }

set -eo pipefail

# Claude Code pipes JSON on stdin with keys like cwd, session_id, model, etc.
INPUT="$(cat)"

# --- helpers ------------------------------------------------------------

jq_get() {
    printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null
}

SESSION_ID="$(jq_get '.session_id')"
SESSION_NAME=""
SESSION_FILE=""

# Heartbeat: record (session_id → cwd) so /save and /read can find us.
write_heartbeat() {
    local cwd="$1"
    [ -z "$SESSION_ID" ] && return 0
    [ -z "$cwd" ] && return 0
    local dir="$HOME/.claude/runtime"
    mkdir -p "$dir" 2>/dev/null || return 0
    printf '{"cwd":"%s","ts":%s}\n' "$cwd" "$(date +%s)" \
        > "$dir/instance-$SESSION_ID.json" 2>/dev/null || true
}

find_current_session() {
    # Populates SESSION_NAME and SESSION_FILE.
    local dir="$1"
    local repo=""
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -d "$dir/.local/sessions" ] || [ -f "$dir/.local/current-session" ]; then
            repo="$dir"
            break
        fi
        dir="$(dirname "$dir")"
    done

    [ -z "$SESSION_ID" ] && return 1

    if [ -n "$repo" ] && [ -f "$repo/.local/current-session-$SESSION_ID" ]; then
        SESSION_NAME="$(head -n1 "$repo/.local/current-session-$SESSION_ID" | tr -d '\n\r')"
        SESSION_FILE="$repo/.local/sessions/$SESSION_NAME.md"
        return 0
    fi
    if [ -f "$HOME/.claude/current-session-$SESSION_ID" ]; then
        SESSION_NAME="$(head -n1 "$HOME/.claude/current-session-$SESSION_ID" | tr -d '\n\r')"
        SESSION_FILE=""
        return 0
    fi
    return 1
}

fmt_bytes() {
    local b="$1"
    if   [ "$b" -lt 1024 ];    then printf "%dB" "$b"
    elif [ "$b" -lt 10240 ];   then awk "BEGIN{printf \"%.1fK\", $b/1024}"
    elif [ "$b" -lt 1048576 ]; then awk "BEGIN{printf \"%dK\", $b/1024}"
    else                            awk "BEGIN{printf \"%.1fM\", $b/1048576}"
    fi
}

# --- gather fields ------------------------------------------------------

CWD="$(jq_get '.cwd')"
[ -z "$CWD" ] && CWD="$(pwd)"

DIR_DISPLAY="${CWD/#$HOME/~}"

write_heartbeat "$CWD"

BRANCH=""
if GIT_OPTIONAL_LOCKS=0 git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(GIT_OPTIONAL_LOCKS=0 git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || echo 'detached')"
fi

find_current_session "$CWD" >/dev/null 2>&1 || true

SESSION_SIZE=""
if [ -n "$SESSION_FILE" ] && [ -f "$SESSION_FILE" ]; then
    bytes="$(wc -c < "$SESSION_FILE" 2>/dev/null | tr -d ' ')"
    [ -n "$bytes" ] && [ "$bytes" -gt 0 ] && SESSION_SIZE="$(fmt_bytes "$bytes")"
fi

MODEL="$(jq_get '.model.display_name // .model.id // empty')"
CTX_PCT="$(jq_get '.context_window.used_percentage')"

# --- colors -------------------------------------------------------------

BOLD="$(tput bold 2>/dev/null || true)"
DIM="$(tput dim 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
CYAN="$(tput setaf 6 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
MAGENTA="$(tput setaf 5 2>/dev/null || true)"
RED="$(tput setaf 1 2>/dev/null || true)"

# --- render -------------------------------------------------------------
# Order: cwd → branch → model → session (size) → ctx%
# Session file size sits next to ctx% so the two "context weight" signals
# — what's on disk to resume, and what's in the live window — read together.

OUT="${BOLD}${CYAN}${DIR_DISPLAY}${RESET}"

[ -n "$BRANCH" ] && OUT="${OUT} ${GREEN}${BRANCH}${RESET}"

[ -n "$MODEL" ] && OUT="${OUT} ${MAGENTA}${MODEL}${RESET}"

if [ -n "$SESSION_NAME" ]; then
    if [ -n "$SESSION_SIZE" ]; then
        OUT="${OUT} ${SESSION_NAME} (${SESSION_SIZE})"
    else
        OUT="${OUT} ${SESSION_NAME}"
    fi
fi

if [ -n "$CTX_PCT" ]; then
    ctx_int="$(printf "%.0f" "$CTX_PCT")"
    if   [ "$ctx_int" -ge 90 ]; then ctx_color="$RED"
    elif [ "$ctx_int" -ge 70 ]; then ctx_color="$YELLOW"
    else                             ctx_color="$GREEN"
    fi
    OUT="${OUT} ${ctx_color}ctx:${ctx_int}%${RESET}"
fi

printf '%s\n' "$OUT"
