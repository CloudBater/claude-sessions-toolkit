#!/usr/bin/env bash
# Claude Code status line — shows the current saved session name.
#
# Reads `.local/current-session` from the working directory tree (walked upward).
# That file is written by the `/save` skill, so your statusline stays in sync
# with the session file you're actually working on.
#
# Falls back to Claude's built-in session name from the JSON piped in on stdin.
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

find_current_session() {
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/.local/current-session" ]; then
            cat "$dir/.local/current-session" | head -1 | tr -d '\n'
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# --- gather fields ------------------------------------------------------

CWD="$(jq_get '.cwd')"
[ -z "$CWD" ] && CWD="$(pwd)"

DIR_DISPLAY="${CWD/#$HOME/~}"

BRANCH=""
if GIT_OPTIONAL_LOCKS=0 git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(GIT_OPTIONAL_LOCKS=0 git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || echo 'detached')"
fi

SESSION_NAME="$(find_current_session "$CWD" 2>/dev/null || true)"
# Disk-only — ignore Claude Code's /rename value (chat-only, doesn't survive)

MODEL="$(jq_get '.model.display_name // .model.id // empty')"

# --- colors -------------------------------------------------------------

BOLD="$(tput bold 2>/dev/null || true)"
DIM="$(tput dim 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"
CYAN="$(tput setaf 6 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
MAGENTA="$(tput setaf 5 2>/dev/null || true)"

# --- render -------------------------------------------------------------

OUT="${BOLD}${CYAN}${DIR_DISPLAY}${RESET}"

[ -n "$BRANCH" ] && OUT="${OUT} ${GREEN}${BRANCH}${RESET}"

if [ -n "$SESSION_NAME" ]; then
    OUT="${OUT} ${YELLOW}★ ${SESSION_NAME}${RESET}"
fi

[ -n "$MODEL" ] && OUT="${OUT} ${DIM}${MAGENTA}${MODEL}${RESET}"

printf '%s\n' "$OUT"
