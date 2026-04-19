#!/usr/bin/env bash
# preview.sh - Dynamically fetches preview info for opencode sessions
# Usage: bash preview.sh "<tab-delimited fzf line>"
#
# Input format (minimal): session_id|title|directory|time_updated|name
# This script dynamically queries all extra information from the DB

set -euo pipefail

DB_PATH="${HOME}/.local/share/opencode/opencode.db"

# Color codes (self-contained)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Parse input - extract session_id from first field
INPUT="${1:-}"
SESSION_ID="${INPUT%%	*}" # First tab-delimited field

if [[ -z "$SESSION_ID" ]]; then
	echo -e "${RED}No session selected${RESET}"
	exit 0
fi

# ─── Dynamic DB queries for preview info ──────────────────────────────────────────

# Get all session details
SESSION_DATA=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
           s.permission, p.worktree, p.name
    FROM session s
    JOIN project p ON s.project_id = p.id
    WHERE s.id = '${SESSION_ID}';
" 2>/dev/null) || true

if [[ -z "$SESSION_DATA" ]]; then
	echo -e "${RED}Session not found: ${SESSION_ID}${RESET}"
	exit 0
fi

IFS='|' read -r id title directory time_updated time_created permission worktree project_name <<<"$SESSION_DATA"

# Get status (from latest message + parts)
STATUS=$(sqlite3 "$DB_PATH" "
    SELECT CASE
        WHEN (
            SELECT COUNT(*) FROM part p
            WHERE p.session_id = '${SESSION_ID}'
              AND json_extract(p.data, '\$.type') = 'tool'
              AND json_extract(p.data, '\$.tool') IN ('question','plan_exit')
              AND json_extract(p.data, '\$.state.status') = 'running'
              AND p.message_id = (
                  SELECT id FROM message WHERE session_id = '${SESSION_ID}'
                  ORDER BY time_created DESC LIMIT 1
              )
        ) > 0 THEN 'needs-input'
        WHEN (
            SELECT COUNT(*) FROM part p
            WHERE p.session_id = '${SESSION_ID}'
              AND json_extract(p.data, '\$.type') = 'tool'
              AND json_extract(p.data, '\$.state.status') = 'error'
              AND p.message_id = (
                  SELECT id FROM message WHERE session_id = '${SESSION_ID}'
                  ORDER BY time_created DESC LIMIT 1
              )
        ) > 0 THEN 'error'
        WHEN (
            SELECT json_extract(data, '\$.role') FROM message
            WHERE session_id = '${SESSION_ID}'
            ORDER BY time_created DESC LIMIT 1
        ) = 'assistant' AND (
            SELECT json_extract(data, '\$.time.completed') FROM message
            WHERE session_id = '${SESSION_ID}'
            ORDER BY time_created DESC LIMIT 1
        ) IS NULL THEN 'working'
        WHEN (
            SELECT json_extract(data, '\$.role') FROM message
            WHERE session_id = '${SESSION_ID}'
            ORDER BY time_created DESC LIMIT 1
        ) = 'user' THEN 'working'
        ELSE 'idle'
    END;
")

# Status icon
case "$STATUS" in
needs-input) STATUS_ICON="${YELLOW}🟡${RESET} ${YELLOW}needs-input${RESET}" ;;
error) STATUS_ICON="${RED}🔴${RESET} ${RED}error${RESET}" ;;
working) STATUS_ICON="${GREEN}🟢${RESET} ${GREEN}working${RESET}" ;;
idle) STATUS_ICON="${DIM}⚪${RESET} ${DIM}idle${RESET}" ;;
*) STATUS_ICON="${DIM}⚪${RESET} ${DIM}unknown${RESET}" ;;
esac

# Model (from latest assistant message)
MODEL=$(sqlite3 "$DB_PATH" "
    SELECT json_extract(data, '\$.modelID')
    FROM message
    WHERE session_id = '${SESSION_ID}'
      AND json_extract(data, '\$.role') = 'assistant'
      AND json_extract(data, '\$.modelID') IS NOT NULL
    ORDER BY time_created DESC LIMIT 1;
" 2>/dev/null) || true

# Shorten model name
if [[ -n "$MODEL" ]]; then
	[[ "$MODEL" == *"/"* ]] && MODEL="${MODEL##*/}"
	MODEL="${MODEL#claude-}"
	MODEL="${MODEL#antigravity-}"
	MODEL="${MODEL//codex-/}"
	MODEL="${MODEL%-preview}"
fi
[[ -z "$MODEL" ]] && MODEL="${DIM}(none)${RESET}"

# Relative time
now=$(date +%s)
diff=$((now - time_updated / 1000))
if ((diff < 60)); then
	TIME_AGO="${diff}s ago"
elif ((diff < 3600)); then
	TIME_AGO="$((diff / 60))m ago"
elif ((diff < 86400)); then
	TIME_AGO="$((diff / 3600))h ago"
elif ((diff < 604800)); then
	TIME_AGO="$((diff / 86400))d ago"
else
	TIME_AGO=$(date -d "@$((time_updated / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$time_updated")
fi

# Child session count (if needed)
CHILD_COUNT=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM session
    WHERE parent_id = '${SESSION_ID}' AND time_archived IS NULL;
")

# Last message preview
LAST_MSG=$(sqlite3 "$DB_PATH" "
    SELECT json_extract(p.data, '\$.text')
    FROM part p
    JOIN message m ON p.message_id = m.id
    WHERE p.session_id = '${SESSION_ID}'
      AND json_extract(p.data, '\$.type') = 'text'
      AND json_extract(p.data, '\$.text') IS NOT NULL
      AND json_extract(p.data, '\$.text') != ''
      AND json_extract(p.data, '\$.text') NOT LIKE '<%'
    ORDER BY m.time_created DESC, p.time_created DESC
    LIMIT 1;
" 2>/dev/null) || true
[[ -z "$LAST_MSG" ]] && LAST_MSG="${DIM}(no messages)${RESET}"
# Truncate
if [[ ${#LAST_MSG} -gt 300 ]]; then
	LAST_MSG="${LAST_MSG:0:300}${DIM}...${RESET}"
fi

# Modified files (distinct)
MODIFIED_FILES=$(sqlite3 "$DB_PATH" "
    SELECT DISTINCT
      COALESCE(
        json_extract(p.data, '\$.files'),
        json_extract(p.data, '\$.state.input.filePath')
      ) as file_raw
    FROM part p
    WHERE p.session_id = '${SESSION_ID}'
      AND (
        (json_extract(p.data, '\$.type') = 'patch' AND json_extract(p.data, '\$.files') IS NOT NULL)
        OR
        (json_extract(p.data, '\$.tool') IN ('edit', 'write', 'apply_patch')
         AND json_extract(p.data, '\$.state.status') = 'completed')
      );
" 2>/dev/null) || true

# Child sessions list
CHILD_SESSIONS=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.id, s.title, s.directory
    FROM session s
    WHERE s.parent_id = '${SESSION_ID}' AND s.time_archived IS NULL
    ORDER BY s.time_created DESC
    LIMIT 5;
" 2>/dev/null) || true

# ─── Output ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}${WHITE}Session:${RESET} ${title}"
echo -e "${WHITE}ID:${RESET}       ${DIM}${id}${RESET}"
echo -e "${WHITE}Status:${RESET}   ${STATUS_ICON}"
echo -e "${WHITE}Model:${RESET}    ${MODEL}"
echo -e "${WHITE}Dir:${RESET}      ${DIM}${directory}${RESET}"
echo -e "${WHITE}Updated:${RESET}  ${TIME_AGO}"
echo -e "${WHITE}Children:${RESET} ${CHILD_COUNT}"
echo ""
echo -e "${BOLD}${WHITE}Last Message:${RESET}"
echo -e "${DIM}${LAST_MSG}${RESET}"
echo ""

# Modified files
if [[ -n "$MODIFIED_FILES" ]]; then
	file_count=$(echo "$MODIFIED_FILES" | wc -l)
	echo -e "${BOLD}${WHITE}Modified Files (${file_count}):${RESET}"
	echo "$MODIFIED_FILES" | head -10 | while read -r f; do
		echo -e "  ${CYAN}${f}${RESET}"
	done
	if ((file_count > 10)); then
		echo -e "  ${DIM}... and $((file_count - 10)) more${RESET}"
	fi
else
	echo -e "${BOLD}${WHITE}Modified Files:${RESET} ${DIM}(none)${RESET}"
fi
echo ""

# Child sessions (only show count, not the list itself since you said you don't need child session info)
if [[ "$CHILD_COUNT" -gt 0 ]]; then
	echo -e "${BOLD}${WHITE}Child Sessions:${RESET} ${DIM}${CHILD_COUNT} child session(s) (info only)${RESET}"
else
	echo -e "${BOLD}${WHITE}Child Sessions:${RESET} ${DIM}(none)${RESET}"
fi
echo ""
