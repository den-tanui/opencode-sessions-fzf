#!/usr/bin/env bash
# dir_preview.sh - Preview for directory in opencode-sessions
# Usage: bash dir_preview.sh "<fzf line>"

set -euo pipefail

DB_PATH="${HOME}/.local/share/opencode/opencode.db"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Parse input - first field before tab
INPUT="${1:-}"
DIRECTORY=$(echo "$INPUT" | head -1 | cut -d$'\t' -f1 | xargs)

if [[ -z "$DIRECTORY" ]]; then
	echo -e "${RED}No directory${RESET}"
	exit 0
fi

# Get directory stats
STATS=$(sqlite3 -separator '|' "$DB_PATH" "
SELECT 
  COUNT(*) as total_sessions,
  SUM(CASE WHEN parent_id IS NULL THEN 1 ELSE 0 END) as parent_sessions,
  SUM(CASE WHEN parent_id IS NOT NULL THEN 1 ELSE 0 END) as child_sessions,
  MAX(time_updated) as latest,
  MIN(time_created) as oldest
FROM session 
WHERE directory = '$DIRECTORY' AND time_archived IS NULL;
" 2>/dev/null) || true

IFS='|' read -r total parent child latest oldest <<<"$STATS"

# Format time
format_time() {
	local ts="$1"
	[[ -z "$ts" || "$ts" == "0" ]] && echo "never"
	now=$(date +%s)
	diff=$((now - ts / 1000))
	((diff < 60)) && echo "${diff}s ago" || ((diff < 3600)) && echo "$((diff / 60))m ago" ||
		((diff < 86400)) && echo "$((diff / 3600))h ago" || ((diff < 604800)) && echo "$((diff / 86400))d ago" ||
		echo "$(date -d "@$((ts / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$ts")"
}

latest_fmtd=$(format_time "$latest")
oldest_fmtd=$(format_time "$oldest")

# Get recent sessions in this directory
RECENT=$(sqlite3 "$DB_PATH" "
SELECT s.id, s.title, s.time_updated
FROM session s
WHERE s.directory = '$DIRECTORY' AND s.time_archived IS NULL AND s.parent_id IS NULL
ORDER BY s.time_updated DESC
LIMIT 5;
" 2>/dev/null) || true

# Output
echo -e "${BOLD}${WHITE}Directory:${RESET} ${DIRECTORY}"
echo -e "${WHITE}Total Sessions:${RESET} ${total:-0}"
echo -e "${WHITE}Parent Sessions:${RESET} ${parent:-0}"
echo -e "${WHITE}Child Sessions:${RESET} ${child:-0}"
echo -e "${WHITE}Latest Update:${RESET} ${latest_fmtd}"
echo -e "${WHITE}First Created:${RESET} ${oldest_fmtd}"
echo ""

if [[ -n "$RECENT" ]]; then
	echo -e "${BOLD}${WHITE}Recent Sessions:${RESET}"
	echo "$RECENT" | while IFS='|' read -r sid stitle stime; do
		stime_fmtd=$(format_time "$stime")
		stitle_short="${stitle:0:50}"
		[[ ${#stitle} -gt 50 ]] && stitle_short="${stitle_short}..."
		echo -e "  ${CYAN}${sid:0:20}...${RESET} ${stime_fmtd} - ${stitle_short}"
	done
else
	echo -e "${BOLD}${WHITE}Recent Sessions:${RESET} ${DIM}(none)${RESET}"
fi
echo ""
