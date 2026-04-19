#!/usr/bin/env bash
# opencode_sessions.sh - Browse opencode sessions with fzf
#
# Usage:
#   ./bin/opencode_sessions.sh              # Interactive - sessions
#   ./bin/opencode_sessions.sh --list         # List sessions
#   ./bin/opencode_sessions.sh --list --directories  # List all directories
#
# Key shortcuts in interactive mode:
#   Enter   - Resume session (cd + exec in tty, new session in tmux)
#   Ctrl-O  - Open in new tmux window (tmux only)
#   Alt-D   - Toggle between sessions and directories view
#   Alt-Y   - Copy session ID to clipboard
#   ?       - Toggle preview

set -euo pipefail

# ─── Script directory ────────────────────────────────────────────────────────────────
if [[ -n "${TMUX_PLUGIN:-}" ]]; then
	SCRIPT_DIR="${TMUX_PLUGIN}"
else
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
fi

source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/db.sh"

# ─── Configuration ────────────────────────────────────────────────────────────────
DB_PATH="${HOME}/.local/share/opencode/opencode.db"
PREVIEW_SCRIPT="${SCRIPT_DIR}/scripts/preview.sh"
DIR_PREVIEW_SCRIPT="${SCRIPT_DIR}/scripts/dir_preview.sh"

get_tmux_option() {
	local option="$1"
	local default="$2"
	local value
	value=$(tmux show-option -gqv "$option" 2>/dev/null)
	echo "${value:-$default}"
}

is_in_tmux() { [[ -n "${TMUX:-}" ]]; }
get_current_tmux_session() {
	if is_in_tmux; then tmux display-message -p '#S' 2>/dev/null; fi
}

DAYS_FILTER=$(get_tmux_option "@opencode-sessions-days" "7")
FZF_OPTS=$(get_tmux_option "@opencode-sessions-fzf-opts" "--height 100% --ansi --layout=reverse --border")

# Check if running inside a popup (to prevent recursive popup spawns)
if [[ "${OPENCODE_POPUP:-}" == "1" ]]; then
	IS_POPUP=true
else
	IS_POPUP=false
fi

# In popup mode, default to sessions view unless --directories is passed
# This allows the reload binding to work
if [[ "$IS_POPUP" == "true" ]] && [[ "$MODE" == "interactive" ]]; then
	# In popup interactive mode - will be handled in main
	:
fi

# ─── Argument parsing ────────────────────────────────────────────────────────
MODE="interactive" # sessions | directories
SHOW_ALL=true      # Default to show all, use --days to limit
DIR_FILTER=""
DAYS_OVERRIDE="" # If --days specified, use this instead of tmux option
TMUX_POPUP=false
POPUP_WIDTH="80%"
POPUP_HEIGHT="80%"
POPUP_BORDER=false

# Pre-scan for --tmux to determine if popup options are allowed
TMUX_FLAG_SEEN=false
for arg in "$@"; do
	[[ "$arg" == "--tmux" ]] && TMUX_FLAG_SEEN=true
done

# Auto-detect tmux: if running inside tmux and --tmux not explicitly passed, use popup mode
if is_in_tmux && [[ "$TMUX_FLAG_SEEN" != "true" ]]; then
	TMUX_POPUP=true
fi

# Error function for invalid flag combinations
invalid_popup_flag() {
	echo "Error: $1 is only available with --tmux flag" >&2
	exit 1
}

# Toggle: cycle through views
# Toggle: produce the reload command for fzf
# default ↔ --directories ↔ --dir
get_toggle_cmd() {
	if [[ -n "$DIR_FILTER" ]]; then
		# Was in filtered sessions (--dir), go to directories
		echo "bash '${0}' --directories"
	elif [[ "$MODE" == "directories" ]]; then
		# Was in directories, go back to the default (or the previously selected dir would be filtered)
		# Check if there's a cached dir from temp file
		if [[ -f /tmp/opencode_selected_dir ]]; then
			local cached_dir
			cached_dir=$(cat /tmp/opencode_selected_dir 2>/dev/null)
			if [[ -n "$cached_dir" ]]; then
				echo "bash '${0}' --dir '${cached_dir}'"
			else
				echo "bash '${0}'"
			fi
		else
			echo "bash '${0}'"
		fi
	else
		# Was in default, go to directories
		echo "bash '${0}' --directories"
	fi
}

# Get enter action for directory selection
get_enter_dir_cmd() {
	local dir="$1"
	if is_in_tmux; then
		echo "bash '${SCRIPT_DIR}/lib/db.sh' && source '${SCRIPT_DIR}/lib/helpers.sh' && DB_PATH='${DB_PATH}' handle_session_tmux_new '${dir}'"
	else
		echo "bash '${SCRIPT_DIR}/lib/db.sh' && source '${SCRIPT_DIR}/lib/helpers.sh' && DB_PATH='${DB_PATH}' handle_session_tty '${dir}'"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--toggle-view)
		# Cycle between views - output toggle command and exit (fzf reload replaces process)
		eval $(get_toggle_cmd)
		exit 0
		;;
	--select-dir)
		# Select directory to show sessions
		SELECTED_DIR="$2"
		shift 2
		;;
	--list)
		MODE="list"
		shift
		;;
	--all)
		SHOW_ALL=true
		shift
		;;
	--directories)
		MODE="directories"
		shift
		;;
	--dir)
		DIR_FILTER="$2"
		shift 2
		;;
	--days)
		DAYS_OVERRIDE="$2"
		SHOW_ALL=false # --days overrides the --all default
		shift 2
		;;
	--new-window)
		NEW_WINDOW_MODE=true
		shift
		;;
	--tmux)
		TMUX_POPUP=true
		shift
		;;
	--width)
		[[ "$TMUX_FLAG_SEEN" != "true" ]] && invalid_popup_flag "--width"
		POPUP_WIDTH="$2"
		shift 2
		;;
	--height)
		[[ "$TMUX_FLAG_SEEN" != "true" ]] && invalid_popup_flag "--height"
		POPUP_HEIGHT="$2"
		shift 2
		;;
	--border)
		[[ "$TMUX_FLAG_SEEN" != "true" ]] && invalid_popup_flag "--border"
		POPUP_BORDER=true
		shift
		;;
	-h | --help)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "Options:"
		echo "  --list          List sessions (use with --directories for dirs)"
		echo "  --directories   Show directories instead of sessions"
		echo "  --dir DIR       Filter by directory"
		echo "  --days N        Days to show (default: all)"
		echo "  --all           Show all sessions"
		echo "  --tmux          Run in tmux popup window"
		echo "    --width WIDTH   Popup width (e.g., 80%)"
		echo "    --height HEIGHT Popup height (e.g., 80%)"
		echo "    --border        Show popup border"
		exit 0
		;;
	*)
		echo "Unknown: $1" >&2
		exit 1
		;;
	esac
done

# ─── Validation ────────────────────────────────────────────────────────────────
[[ ! -f "$DB_PATH" ]] && {
	echo -e "${RED}DB not found: $DB_PATH${RESET}"
	exit 1
}
command -v fzf &>/dev/null || {
	echo -e "${RED}fzf required${RESET}"
	exit 1
}

# Compute effective days filter - --days overrides tmux option
if [[ -n "$DAYS_OVERRIDE" ]]; then
	DAYS_FILTER="$DAYS_OVERRIDE"
fi

# ─── Format functions ────────────────────────────────────────────────────────
format_session() {
	while IFS='|' read -r id title dir time_updated name; do
		now=$(date +%s)
		diff=$((now - time_updated / 1000))
		((diff < 60)) && time_ago="${diff}s" || ((diff < 3600)) && time_ago="$((diff / 60))m" ||
			((diff < 86400)) && time_ago="$((diff / 3600))h" || ((diff < 604800)) && time_ago="$((diff / 86400))d" ||
			time_ago=$(date -d "@$((time_updated / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$time_updated")
		display_name="${name:0:20}"
		[[ ${#name} -gt 20 ]] && display_name="${display_name:0:17}..."
		printf '%s\t%s %s %s\n' "$id" "$time_ago" "$display_name" "$title"
	done
}

format_directory() {
	while IFS='|' read -r dir count; do
		short_dir="${dir##*/}"
		printf '%s\t%s (%s sessions)\n' "$dir" "$short_dir" "$count"
	done
}

# ─── List mode ────────────────────────────────────────────────────────────────
run_list() {
	if [[ "$MODE" == "directories" ]]; then
		query_all_directories "$DB_PATH" | format_directory
	elif [[ -n "$DIR_FILTER" ]]; then
		# --dir shows ALL sessions from that directory (no time filter)
		query_dir_sessions "$DB_PATH" "$DIR_FILTER" | format_session
	else
		query_all_sessions "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" "$DIR_FILTER" | format_session
	fi
}

# ─── Interactive mode ────────────────────────────────────────────────────────
run_interactive() {
	# Determine if we're showing directories or sessions
	if [[ "$MODE" == "directories" ]]; then
		run_interactive_directories
	else
		run_interactive_sessions "$DIR_FILTER"
	fi
}

# ─── Interactive directories mode ───────────────────────────────────────────
run_interactive_directories() {
	echo -e "${CYAN}Loading directories...${RESET}" >&2

	cache_file=$(mktemp)
	trap 'rm -f "$cache_file"' EXIT

	query_all_directories "$DB_PATH" >"$cache_file"

	if [[ ! -s "$cache_file" ]]; then
		echo -e "${YELLOW}No directories${RESET}"
		exit 0
	fi

	count=$(wc -l <"$cache_file")
	echo -e "${DIM}${count} directories${RESET}" >&2

	# For directories: Enter to view sessions in that directory
	# Alt-D to return to default sessions view
	header="alt-d: sessions | ?: preview"
	local enter_cmd="enter:change-prompt(Sessions> )+reload(bash '${0}' --dir '\$(echo {} | cut -f1)')"
	local selected
	selected=$(format_directory <"$cache_file" | fzf \
		$FZF_OPTS \
		--expect=alt-d \
		--with-nth 2.. \
		--border-label " Directories " \
		--preview "bash '${DIR_PREVIEW_SCRIPT}' {}" \
		--preview-window "right:50%,border-left" \
		--delimiter '\t' \
		--prompt="Dirs> " \
		--footer "$footer" \
		--bind "?:toggle-preview" \
		--bind "alt-d:reload(bash '${0}' --toggle-view)" \
		--bind "$enter_cmd" \
		2>/dev/null) || true

	[[ -z "$selected" ]] && exit 0

	key_pressed=$(echo "$selected" | head -1)
	dir_selected=$(echo "$selected" | tail -n +2)
	directory=$(echo "$dir_selected" | cut -f1)

	[[ -z "$directory" ]] && exit 0

	# Store directory for toggle back
	echo "$directory" > /tmp/opencode_selected_dir

	# Handle Alt-D toggle (return to default)
	if [[ "$key_pressed" == "alt-d" ]]; then
		eval $(get_toggle_cmd)
		exit 0
	fi

	# Enter pressed - reload to sessions filtered by this directory
	exec bash "${0}" --dir "$directory"
}

# ─── Interactive sessions mode ────────────────────────────────────────────────
run_interactive_sessions() {
	local dir_filter="${1:-}"

	echo -e "${CYAN}Loading sessions...${RESET}" >&2

	cache_file=$(mktemp)
	sorted_file=$(mktemp)
	trap 'rm -f "$cache_file" "$sorted_file"' EXIT

	query_all_sessions "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" "$dir_filter" >"$cache_file"

	if [[ ! -s "$cache_file" ]]; then
		echo -e "${YELLOW}No sessions${RESET}"
		exit 0
	fi

	count=$(wc -l <"$cache_file")
	filter_info=""
	[[ -n "$dir_filter" ]] && filter_info=" [$dir_filter]"
	echo -e "${DIM}${count} sessions${filter_info}${RESET}" >&2

	sort -t$'\t' -k2,2nr <"$cache_file" >"$sorted_file"

	# Determine Enter behavior based on context
	local enter_action
	if is_in_tmux; then
		# In tmux: Enter = create new session and switch to it
		enter_action="enter:execute-silent('${SCRIPT_DIR}/scripts/tmux' --session {})"
	else
		# Not in tmux: Enter = cd to directory and exec opencode
		enter_action="enter:execute-silent(source '${SCRIPT_DIR}/lib/db.sh' && source '${SCRIPT_DIR}/lib/helpers.sh' && DB_PATH='${DB_PATH}' handle_session_tty \$(echo {} | cut -f1))"
	fi

	# Custom prompt for directory-filtered view
	local prompt="Select: "
local border_label=" Sessions "
	local header="alt-d: directories | ?: preview"
	if [[ -n "$dir_filter" ]]; then
		local short_dir="${dir_filter##*/}"
		prompt="[${short_dir}] "
		border_label=" Sessions [${short_dir}] "
		header="alt-d: directories | ?: preview"
	fi

	footer="Enter: resume | Alt+Y: copy | ?: preview"

	local selected
	selected=$(
		format_session <"$sorted_file" | fzf \
			$FZF_OPTS \
			--expect=ctrl-o \
			--with-nth 2.. \
			--border-label "$border_label" \
			--header "$header" \
			--preview "bash '${PREVIEW_SCRIPT}' {}" \
			--preview-window "right:60%,border-left" \
			--delimiter '\t' \
			--prompt="$prompt" \
			--footer "$footer" \
			--bind "?:toggle-preview" \
			--bind "alt-d:change-prompt(Dirs> )+reload(bash '${0}' --toggle-view)" \
			--bind "alt-y:execute(echo {1} | $(copy_to_clipboard))" \
			--bind "$enter_action" \
			2>/dev/null
	) || true

	[[ -z "$selected" ]] && echo -e "${DIM}No selection${RESET}" && exit 0

	key_pressed=$(echo "$selected" | head -1)
	session_line=$(echo "$selected" | tail -n +2)
	session_id=$(echo "$session_line" | cut -f1)

	[[ -z "$session_id" ]] && exit 0

	# Handle Ctrl-O (new window in tmux)
	if [[ "$key_pressed" == "ctrl-o" ]] && is_in_tmux; then
		handle_session_tmux_new_window "$session_id"
		exit 0
	fi

	# Normal resume based on context
	if is_in_tmux; then
		handle_session_tmux_new "$session_id"
	else
		handle_session_tty "$session_id"
	fi
}

# ─── Handlers ────────────────────────────────────────────────────────────────
# Called from tty - cd to directory and exec opencode
handle_session_tty() {
	local session_id="$1"
	directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session WHERE id = '$session_id';")
	[[ -z "$directory" ]] && {
		echo -e "${RED}Not found: $session_id${RESET}"
		exit 1
	}
	[[ ! -d "$directory" ]] && {
		echo -e "${RED}Missing: $directory${RESET}"
		exit 1
	}
	echo -e "${GREEN}$session_id${RESET}"
	echo -e "${DIM}$directory${RESET}"
	cd "$directory" && exec opencode -s "$session_id"
}

# Called from tmux - create new session and switch to it
handle_session_tmux_new() {
	local session_id="$1"
	directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session WHERE id = '$session_id';")
	[[ -z "$directory" ]] && {
		echo -e "${RED}Not found: $session_id${RESET}"
		exit 1
	}
	[[ ! -d "$directory" ]] && {
		echo -e "${RED}Missing: $directory${RESET}"
		exit 1
	}

	session_name=$(derive_repo_name "$directory")
	use_prefix=$(get_tmux_option "@opencode-sessions-prefix" "false")
	[[ "$use_prefix" != "false" ]] && session_name="${use_prefix}${session_name}"

	echo -e "${GREEN}$session_id${RESET}"
	echo -e "${DIM}$directory${RESET}"
	echo -e "${DIM}Session: $session_name${RESET}"

	if tmux has-session -t "$session_name" 2>/dev/null; then
		tmux new-window -t "$session_name" -c "$directory" -n "opencode" "exec opencode -s ${session_id}"
		tmux switch-client -t "$session_name"
	else
		tmux new-session -d -s "$session_name" -c "$directory" "exec opencode -s ${session_id}"
		tmux switch-client -t "$session_name"
	fi
}

# Called from tmux with Ctrl-O - open in new window without switching
handle_session_tmux_new_window() {
	local session_id="$1"
	directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session WHERE id = '$session_id';")
	[[ -z "$directory" ]] && {
		echo -e "${RED}Not found: $session_id${RESET}"
		exit 1
	}
	[[ ! -d "$directory" ]] && {
		echo -e "${RED}Missing: $directory${RESET}"
		exit 1
	}

	current_session=$(get_current_tmux_session)
	echo -e "${GREEN}$session_id${RESET}"
	echo -e "${DIM}$directory${RESET}"
	tmux new-window -t "$current_session" -c "$directory" -n "opencode" "exec opencode -s ${session_id}"
}

# ─── Main ──────────────────────────────────────────────────────────────────────

# Handle --tmux flag: run in tmux popup using fzf's built-in --tmux option
# Uses interactive mode functions for proper cycling support
if [[ "$TMUX_POPUP" == "true" ]] && is_in_tmux && [[ "$IS_POPUP" != "true" ]]; then
	# Always show border by default in --tmux mode
	border_flag="--border"

	# Set flag to prevent recursive popup spawns
	export OPENCODE_POPUP=1
	export OPENCODE_TMUX_POPUP=1

	# Build fzf options for tmux popup - always has border
	FZF_POPUP_OPTS="--ansi --layout=reverse --tmux ${POPUP_WIDTH},${POPUP_HEIGHT} $border_flag"

	# Handle --directories flag in --tmux mode
	if [[ "$MODE" == "directories" ]]; then
		# Run directories view in popup
		cache_file=$(mktemp)
		trap 'rm -f "$cache_file"' EXIT

		query_all_directories "$DB_PATH" >"$cache_file"
		selected=$(format_directory <"$cache_file" | fzf $FZF_POPUP_OPTS \
			--with-nth 2.. \
			--border-label " Directories " \
			--preview "bash '${DIR_PREVIEW_SCRIPT}' {}" \
			--preview-window "right:50%,border-left" \
			--delimiter '\t' \
			--prompt="Select dir: " \
			--footer "Enter: filter | ?: preview" \
			--bind "?:toggle-preview" \
			--bind "enter:execute(echo {1} > /tmp/opencode_dir_select)" \
			2>/dev/null) || true

		if [[ -n "$selected" ]]; then
			DIR_FILTER=$(echo "$selected" | cut -f1)
			# Continue to sessions view with filter
		else
			# Check if Enter was pressed to clear filter
			if [[ -f /tmp/opencode_dir_select ]]; then
				rm -f /tmp/opencode_dir_select
				DIR_FILTER=""
			fi
		fi
	fi

	# Cache files for sessions view
	cache_file=$(mktemp)
	sorted_file=$(mktemp)
	trap 'rm -f "$cache_file" "$sorted_file"' EXIT

	# Start the popup loop - use while to allow cycling
	while true; do
		# Get sessions data (filtered by DIR_FILTER if set)
		query_all_sessions "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" "$DIR_FILTER" >"$cache_file"
		sort -t$'\t' -k2,2nr <"$cache_file" >"$sorted_file"
		mv "$sorted_file" "$cache_file"

		# Build border label - show directory filter if active
		border_label=" Sessions "
		header="alt-d: directories | ?: preview"
		prompt="Select: "
		[[ -n "$DIR_FILTER" ]] && border_label=" Sessions " && header="alt-d: directories | ?: preview"

		selected=$(format_session <"$cache_file" | fzf $FZF_POPUP_OPTS \
			--multi \
			--expect=alt-o \
			--with-nth 2.. \
			--border-label "$border_label" \
			--header "$header" \
			--preview "bash '${PREVIEW_SCRIPT}' {}" \
			--preview-window "right:60%,border-left" \
			--delimiter '\t' \
			--prompt="$prompt" \
			--footer "Enter: resume | Alt+Y: copy | Alt-O: new-window | TAB: multi-select | ?: preview" \
			--bind "?:toggle-preview" \
			--bind "alt-y:execute(echo {1} | $(copy_to_clipboard))" \
			--bind "alt-d:change-prompt(Dirs> )+reload(bash '${0}' --toggle-view)" \
			--bind "alt-o:execute-silent('${SCRIPT_DIR}/scripts/tmux' --new-window {})" \
			--bind "enter:execute-silent('${SCRIPT_DIR}/scripts/tmux' --session {})" \
			2>/dev/null) || true

		[[ -z "$selected" ]] && break

		key_pressed=$(echo "$selected" | head -1)
		session_lines=$(echo "$selected" | tail -n +2)

		# Handle key actions
		if [[ "$key_pressed" == "alt-o" ]]; then
			# Alt-O: new windows for all selected (without switching)
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				session_id=$(echo "$line" | cut -f1)
				handle_session_tmux_new_window "$session_id"
				sleep 0.3
			done <<<"$session_lines"
			break
		elif [[ "$key_pressed" == "alt-d" ]]; then
			# Alt-D: switch to directories view
			query_all_directories "$DB_PATH" >"$cache_file"
			dir_selected=$(format_directory <"$cache_file" | fzf $FZF_POPUP_OPTS \
				--with-nth 2.. \
				--border-label " Directories " \
				--preview "bash '${DIR_PREVIEW_SCRIPT}' {}" \
				--preview-window "right:50%,border-left" \
				--delimiter '\t' \
				--prompt="Select dir: " \
				--footer "Enter: filter | Alt-D: toggle | ?: preview" \
				--bind "?:toggle-preview" \
				--bind "enter:execute(echo {1} > /tmp/opencode_dir_select)" \
				2>/dev/null) || true

			if [[ -n "$dir_selected" ]]; then
				DIR_FILTER=$(echo "$dir_selected" | cut -f1)
				# Clear filter with Alt-D to toggle back to all sessions
				# Continue loop to show sessions for this directory
				continue
			else
				# Check if Enter was pressed (set by bind above)
				if [[ -f /tmp/opencode_dir_select ]]; then
					rm -f /tmp/opencode_dir_select
					DIR_FILTER=""
				fi
				# No directory selected, stay in sessions view
				continue
			fi
		else
			# Enter pressed - handle all selected sessions sequentially
			while IFS= read -r line; do
				[[ -z "$line" ]] && continue
				session_id=$(echo "$line" | cut -f1)
				handle_session_tmux_new "$session_id"
				sleep 0.3
			done <<<"$session_lines"
			break
		fi
	done
	exit 0
fi

if [[ "$MODE" == "list" ]]; then
	run_list
else
	run_interactive
fi
