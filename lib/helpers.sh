#!/usr/bin/env bash
# Helper functions for opencode-sessions

# Get total session count
get_total_count() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	sqlite3 "$db_path" "SELECT COUNT(*) FROM session WHERE time_archived IS NULL AND parent_id IS NULL;"
}

get_sort_label() {
	case "$1" in
	time) echo "time" ;;
	directory) echo "directory" ;;
	status) echo "status (running, idle, dead)" ;;
	*) echo "time" ;;
	esac
}

# Derive repo name from directory
derive_repo_name() {
	local dir="$1"
	if [[ "$dir" == *"/.worktrees/"* ]]; then
		basename "${dir%%/.worktrees/*}"
	else
		basename "$dir"
	fi
}

# Relative time formatting
relative_time() {
	local ts="$1"
	local now
	now=$(date +%s)
	local diff=$((now - ts / 1000))
	if ((diff < 60)); then
		echo "${diff}s ago"
	elif ((diff < 3600)); then
		echo "$((diff / 60))m ago"
	elif ((diff < 86400)); then
		echo "$((diff / 3600))h ago"
	elif ((diff < 604800)); then
		echo "$((diff / 86400))d ago"
	else
		date -d "@$((ts / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$ts"
	fi
}

# Shorten model name
shorten_model() {
	local model="$1"
	[[ -z "$model" ]] && return
	[[ "$model" == *"/"* ]] && model="${model##*/}"
	model="${model#claude-}"
	model="${model#antigravity-}"
	model="${model//codex-/}"
	model="${model%-preview}"
	echo "$model"
}

# Compute status from session flags
compute_status() {
	local has_rq="$1" has_cq="$2" has_err="$3" role="$4" completed="$5"
	if ((has_rq > 0 || has_cq > 0)); then
		echo "needs-input"
	elif ((has_err > 0)); then
		echo "error"
	elif [[ "$role" == "assistant" && "$completed" == "null" ]]; then
		echo "working"
	elif [[ "$role" == "user" ]]; then
		echo "working"
	else
		echo "idle"
	fi
}

# Status icon based on session status
status_icon() {
	case "$1" in
	needs-input) echo -e "${YELLOW}🟡${RESET}" ;;
	error) echo -e "${RED}🔴${RESET}" ;;
	working) echo -e "${GREEN}🟢${RESET}" ;;
	idle) echo -e "${DIM}⚪${RESET}" ;;
	*) echo -e "${DIM}⚪${RESET}" ;;
	esac
}

# Status priority for sorting
status_priority() {
	case "$1" in
	working) echo 0 ;;
	idle) echo 1 ;;
	*) echo 2 ;;
	esac
}

# Get clipboard copy command
copy_to_clipboard() {
	if command -v xclip &>/dev/null; then
		echo "xclip -selection clipboard"
	elif command -v wl-copy &>/dev/null; then
		echo "wl-copy"
	elif command -v pbcopy &>/dev/null; then
		echo "pbcopy"
	else
		echo "cat"
	fi
}
