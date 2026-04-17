#!/usr/bin/env bash
# Claude Code status line — shows the current saved session name.
#
# Reads `.local/current-session` from the working directory tree (walked upward).
# That file is written by the `/save` skill, so your statusline stays in sync
# with the session file you're actually working on.
#
# Falls back to `~/.claude/current-session` (global pointer) when no repo-local
# pointer is found — lets the active session name follow you across sibling
# repos. Disk-only; ignores Claude Code's /rename (chat-only).
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

SESSION_NAME=""
SESSION_FILE=""

find_current_session() {
    # Populates SESSION_NAME and SESSION_FILE.
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/.local/current-session" ]; then
            SESSION_NAME="$(head -n1 "$dir/.local/current-session" | tr -d '\n\r')"
            SESSION_FILE="$dir/.local/sessions/$SESSION_NAME.md"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [ -f "$HOME/.claude/current-session" ]; then
        SESSION_NAME="$(head -n1 "$HOME/.claude/current-session" | tr -d '\n\r')"
        # Global fallback: we don't know where the .md lives, so no size.
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

BRANCH=""
if GIT_OPTIONAL_LOCKS=0 git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(GIT_OPTIONAL_LOCKS=0 git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || echo 'detached')"
fi

find_current_session "$CWD" >/dev/null 2>&1 || true
# Disk-only — ignore Claude Code's /rename value (chat-only, doesn't survive)

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
        OUT="${OUT} ${DIM}${SESSION_NAME} (${SESSION_SIZE})${RESET}"
    else
        OUT="${OUT} ${DIM}${SESSION_NAME}${RESET}"
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
