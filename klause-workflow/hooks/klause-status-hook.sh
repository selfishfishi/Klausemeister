#!/usr/bin/env bash
# Write per-worktree meister session state for Klausemeister's UI.
# Invoked by Claude Code hooks; payload arrives on stdin as JSON.
# No-op when KLAUSE_WORKTREE_ID is unset (the session is not a meister).

set -u

[[ -z "${KLAUSE_WORKTREE_ID:-}" ]] && exit 0

STATUS_DIR="${HOME}/.klausemeister/status"
STATUS_FILE="${STATUS_DIR}/${KLAUSE_WORKTREE_ID}.json"

INPUT=""
[[ -t 0 ]] || INPUT=$(cat)

# Extract a top-level string key from the JSON payload via jq.
# Silently degrades to empty string if jq is missing or input is empty —
# hooks must never fail Claude Code, so any parse issue becomes a no-op.
jqget() {
    [[ -z "$INPUT" ]] && return
    command -v jq >/dev/null 2>&1 || return
    printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
}

EVENT=$(jqget hook_event_name)
SESSION_ID=$(jqget session_id)
TOOL_NAME=$(jqget tool_name)
MATCHER=$(jqget matcher)

if [[ "$EVENT" == "SessionEnd" ]]; then
    rm -f "$STATUS_FILE"
    exit 0
fi

case "$EVENT" in
    SessionStart|Stop)
        STATE="idle"
        ;;
    UserPromptSubmit|PreToolUse|PostToolUse)
        STATE="working"
        ;;
    StopFailure)
        STATE="error"
        ;;
    Notification)
        case "$MATCHER" in
            permission_prompt|elicitation_dialog)
                STATE="blocked"
                ;;
            idle_prompt)
                STATE="idle"
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac

mkdir -p "$STATUS_DIR"
TIMESTAMP=$(date +%s)
TMP_FILE=$(mktemp "${STATUS_FILE}.XXXXXX") || exit 0

# jq builds the JSON so special characters in session_id / tool_name
# are escaped correctly.
if command -v jq >/dev/null 2>&1; then
    if [[ -n "$TOOL_NAME" ]]; then
        jq -n \
            --arg state "$STATE" \
            --argjson ts "$TIMESTAMP" \
            --arg sid "$SESSION_ID" \
            --arg tool "$TOOL_NAME" \
            '{state: $state, timestamp: $ts, session_id: $sid, last_tool: $tool}' \
            > "$TMP_FILE" && mv -f "$TMP_FILE" "$STATUS_FILE"
    else
        jq -n \
            --arg state "$STATE" \
            --argjson ts "$TIMESTAMP" \
            --arg sid "$SESSION_ID" \
            '{state: $state, timestamp: $ts, session_id: $sid}' \
            > "$TMP_FILE" && mv -f "$TMP_FILE" "$STATUS_FILE"
    fi
else
    rm -f "$TMP_FILE"
fi

exit 0
