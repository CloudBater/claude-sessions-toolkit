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

# --- rate-limit usage (Pro/Max only; absent until first API response) ---
# rate_limits.{five_hour,seven_day}.{used_percentage, resets_at(epoch s)}.
# Each window may be independently absent — render only what's present.
fmt_reset() {
    # $1 = epoch seconds, $2 = strftime format. BSD (-r) then GNU (-d) fallback.
    local e="$1" f="$2"
    [ -z "$e" ] && return 0
    date -r "$e" "+$f" 2>/dev/null || date -d "@$e" "+$f" 2>/dev/null || true
}

render_limit() {
    # $1 label, $2 used_pct, $3 resets_at(epoch), $4 reset strftime fmt
    local label="$1" pct="$2" reset="$3" rfmt="$4"
    [ -z "$pct" ] && return 0
    local pi; pi="$(printf '%.0f' "$pct")"
    local col="$GREEN"
    if   [ "$pi" -ge 90 ]; then col="$RED"
    elif [ "$pi" -ge 70 ]; then col="$YELLOW"
    fi
    local seg="${col}${label}:${pi}%${RESET}"
    local rt; rt="$(fmt_reset "$reset" "$rfmt")" || true
    [ -n "$rt" ] && seg="${seg}${DIM}↺${rt}${RESET}"
    OUT="${OUT} ${seg}"
}

H5_PCT="$(jq_get '.rate_limits.five_hour.used_percentage')"
H5_RST="$(jq_get '.rate_limits.five_hour.resets_at')"
D7_PCT="$(jq_get '.rate_limits.seven_day.used_percentage')"
D7_RST="$(jq_get '.rate_limits.seven_day.resets_at')"

render_limit "5h" "$H5_PCT" "$H5_RST" "%H:%M"
render_limit "7d" "$D7_PCT" "$D7_RST" "%m/%d %H:%M"

# --- VS Code memory -----------------------------------------------------
# Sum RSS (KB on macOS) of every "Visual Studio Code" process, shown as
# absolute GB + % of total physical RAM. Color: red ≥90%, yellow ≥70%.
# The [V] bracket trick keeps this grep from matching its own ps entry.
# pipefail-safe: `|| true` swallows grep's exit 1 when VS Code isn't running.
VSC_KB="$(ps -axo rss=,command= 2>/dev/null | grep -i '[V]isual Studio Code' | awk '{s+=$1} END{print s+0}' || true)"
if [ -n "$VSC_KB" ] && [ "$VSC_KB" -gt 0 ] 2>/dev/null; then
    VSC_GB="$(awk "BEGIN{printf \"%.1f\", $VSC_KB/1048576}")"
    MEM_TOTAL_B="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    if [ "$MEM_TOTAL_B" -gt 0 ] 2>/dev/null; then
        VSC_PCT="$(awk "BEGIN{printf \"%.0f\", $VSC_KB*1024*100/$MEM_TOTAL_B}")"
        if   [ "$VSC_PCT" -ge 90 ]; then vcol="$RED"
        elif [ "$VSC_PCT" -ge 70 ]; then vcol="$YELLOW"
        else                             vcol="$GREEN"
        fi
        OUT="${OUT} ${vcol}vsc:${VSC_GB}G ${VSC_PCT}%${RESET}"
    else
        OUT="${OUT} ${GREEN}vsc:${VSC_GB}G${RESET}"
    fi
fi

printf '%s\n' "$OUT"
