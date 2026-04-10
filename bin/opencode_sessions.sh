#!/usr/bin/env bash
# opencode_sessions.sh - TPM plugin entry point for browsing opencode sessions
#
# Usage:
#   ./bin/opencode_sessions.sh              # Interactive mode with fzf in tmux popup
#   ./bin/opencode_sessions.sh --list       # List sessions without fzf
#   ./bin/opencode_sessions.sh --copy       # Copy selected session ID to clipboard
#   ./bin/opencode_sessions.sh --multi      # Multi-select mode
#   ./bin/opencode_sessions.sh --filter working  # Only show working sessions
#   ./bin/opencode_sessions.sh --sort status     # Start sorted by status
#
# Dependencies: sqlite3, fzf, opencode

set -euo pipefail

# ─── Script directory resolution ──────────────────────────────────────────────
# Handle both direct execution and TPM sourcing
if [[ -n "${TMUX_PLUGIN:-}" ]]; then
  # Running as TPM plugin - use plugin directory
  SCRIPT_DIR="${TMUX_PLUGIN}"
else
  # Running directly - resolve relative to script location
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
fi

# ─── Source library modules ───────────────────────────────────────────────────
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/db.sh"
source "${SCRIPT_DIR}/lib/format.sh"

# ─── Configuration ──────────────────────────────────────────────────────────────
DB_PATH="${HOME}/.local/share/opencode/opencode.db"
PREVIEW_SCRIPT="${SCRIPT_DIR}/scripts/preview.sh"

# Read tmux options with fallbacks
get_tmux_option() {
  local option="$1"
  local default="$2"
  local value
  value=$(tmux show-option -gqv "$option" 2>/dev/null)
  echo "${value:-$default}"
}

DAYS_FILTER=$(get_tmux_option "@opencode-sessions-days" "7")
SORT_BY=$(get_tmux_option "@opencode-sessions-sort" "time")

# FZF options - passed as single string of options
FZF_OPTS=$(get_tmux_option "@opencode-sessions-fzf-opts" "--height 100% --ansi --layout=reverse --border")

# ─── Argument parsing ─────────────────────────────────────────────────────────
MODE="interactive"
FILTER_STATUS=""
SHOW_ALL=false
DIR_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --list)
    MODE="list"
    shift
    ;;
  --copy)
    MODE="copy"
    shift
    ;;
  --multi)
    MODE="multi"
    shift
    ;;
  --filter)
    FILTER_STATUS="$2"
    shift 2
    ;;
  --sort)
    SORT_BY="$2"
    shift 2
    ;;
  --days)
    DAYS_FILTER="$2"
    shift 2
    ;;
  --all)
    SHOW_ALL=true
    shift
    ;;
  --dir)
    DIR_FILTER="$2"
    shift 2
    ;;
  -h | --help)
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --list          List sessions without fzf"
    echo "  --copy          Copy selected session ID to clipboard"
    echo "  --multi         Multi-select mode (TAB to mark)"
    echo "  --filter STATUS Filter by: working, needs-input, error, idle"
    echo "  --sort FIELD    Initial sort: time (default), directory, status"
    echo "  --dir DIR       Filter by specific directory (exact match)"
    echo "  --days N        Show sessions from last N days (default: 14)"
    echo "  --all           Show all sessions regardless of age"
    echo "  -h, --help      Show this help"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
done

# ─── Validation ───────────────────────────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
  echo -e "${RED}Error: opencode database not found at ${DB_PATH}${RESET}" >&2
  echo "Run opencode at least once to create the database." >&2
  exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
  echo -e "${RED}Error: sqlite3 is required but not installed${RESET}" >&2
  exit 1
fi

if ! command -v fzf &>/dev/null; then
  echo -e "${RED}Error: fzf is required but not installed${RESET}" >&2
  exit 1
fi

if [[ ! -f "$PREVIEW_SCRIPT" ]]; then
  echo -e "${RED}Error: preview.sh not found at ${PREVIEW_SCRIPT}${RESET}" >&2
  exit 1
fi

# ─── List mode ────────────────────────────────────────────────────────────────

run_list() {
  # Get counts for display
  local filtered_count=0
  local total_count=0

  # Count filtered sessions
  filtered_count=$(build_session_data query_all_sessions "$FILTER_STATUS" | wc -l)

  # Get total count if filtering
  if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
    total_count=$(get_total_count "$DB_PATH")
    if [[ "$filtered_count" != "$total_count" ]]; then
      echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}"
    fi
  fi

  echo -e "${WHITE}$(printf '%-8s' 'Status') $(printf '%-10s' 'Updated') $(printf '%-20s' 'Repo') Session Title [Model]${RESET}"
  echo -e "${DIM}$(printf '%.0s─' {1..100})${RESET}"

  build_session_data query_all_sessions "$FILTER_STATUS" | sort_data "$SORT_BY" | format_for_list | while IFS=$'\t' read -r line; do
    echo -e "$line"
  done
}

# ─── Interactive fzf mode ─────────────────────────────────────────────────────

run_interactive() {
  echo -e "${CYAN}Loading sessions...${RESET}" >&2

  # Cache all session data
  local cache_file
  cache_file=$(mktemp)
  trap 'rm -f "$cache_file"' EXIT

  build_session_data query_all_sessions "$FILTER_STATUS" >"$cache_file"

  if [[ ! -s "$cache_file" ]]; then
    echo -e "${YELLOW}No sessions found.${RESET}"
    exit 0
  fi

  # Get counts for display
  local filtered_count
  local total_count=0
  filtered_count=$(wc -l <"$cache_file")

  if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
    total_count=$(get_total_count "$DB_PATH")
    if [[ "$filtered_count" != "$total_count" ]]; then
      echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}" >&2
    fi
  fi

  # Sort the cached data (default: newest first)
  local sorted_file
  sorted_file=$(mktemp)
  trap 'rm -f "$cache_file" "$sorted_file"' EXIT
  sort_data "$SORT_BY" <"$cache_file" >"$sorted_file"

  local fzf_flags=()
  if [[ "$MODE" == "multi" ]]; then
    fzf_flags+=(--multi)
  fi

  # State file for sort cycling
  local sort_state_file
  sort_state_file=$(mktemp)
  case "$SORT_BY" in
  time) echo "0" >"$sort_state_file" ;;
  directory) echo "1" >"$sort_state_file" ;;
  status) echo "2" >"$sort_state_file" ;;
  *) echo "0" >"$sort_state_file" ;;
  esac

  # Cycle script for sort cycling in fzf
  local cycle_script
  cycle_script=$(mktemp)
  trap 'rm -f "$cache_file" "$sorted_file" "$cycle_script" "$sort_state_file" "$cycle_cache"' EXIT

  # Copy cache data to a temp file that cycle script can read
  local cycle_cache
  cycle_cache=$(mktemp)
  cp "$cache_file" "$cycle_cache"

  cat >"$cycle_script" <<CYCLE_EOF
#!/usr/bin/env bash
CACHE_FILE="$cycle_cache"
STATE_FILE="$sort_state_file"

sort_order=("time" "directory" "status")

idx=\$(cat "\$STATE_FILE")
idx=\$(( (idx + 1) % 3 ))
echo "\$idx" > "\$STATE_FILE"

sort_field="\${sort_order[\$idx]}"

format_for_display() {
    while IFS=\$'\\t' read -r id status time_ago repo title model directory child_count; do
        local icon
        case "\$status" in
            needs-input) icon=\$'\\033[0;33m🟡\\033[0m' ;;
            error)       icon=\$'\\033[0;31m🔴\\033[0m' ;;
            working)     icon=\$'\\033[0;32m🟢\\033[0m' ;;
            idle)        icon=\$'\\033[2m⚪\\033[0m' ;;
            *)           icon=\$'\\033[2m⚪\\033[0m' ;;
        esac
        if [[ -n "\$model" ]]; then
            printf '%s\\t%-8s %-10s %-20s %s [%s]\\n' "\$id" "\$icon" "\$time_ago" "\$repo" "\$title" "\$model"
        else
            printf '%s\\t%-8s %-10s %-20s %s\\n' "\$id" "\$icon" "\$time_ago" "\$repo" "\$title"
        fi
    done
}

sort_data() {
    case "\$1" in
        time) cat ;;
        directory) sort -t\$'\\t' -k4,4 -k3,3 ;;
        status)
            while IFS=\$'\\t' read -r id status time_ago repo title model directory child_count; do
                local prio
                case "\$status" in
                    working) prio=0 ;; 
                    idle) prio=1 ;;    
                    *) prio=2 ;;       
                esac
                printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "\$id" "\$prio" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done | sort -t\$'\\t' -k2,2n -k3,3 | while IFS=\$'\\t' read -r id prio time_ago repo title model directory child_count; do
                local actual_status
                case "\$prio" in
                    0) actual_status="working" ;;
                    1) actual_status="idle" ;;
                    *) actual_status="dead" ;;
                esac
                printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "\$id" "\$actual_status" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done
            ;;
    esac
}

sort_data "\$sort_field" < "\$CACHE_FILE" | format_for_display
CYCLE_EOF
  chmod +x "$cycle_script"

  # Run fzf with footer and alt-s sort cycling
  local selected
  selected=$(format_for_display <"$sorted_file" | fzf \
    $FZF_OPTS \
    --with-nth 2.. \
    --border-label "OpenCode Sessions" \
    --preview "bash '${PREVIEW_SCRIPT}' {}" \
    --preview-window "right:60%,border-left" \
    --delimiter '\t' \
    --prompt="Select session: " \
    --footer "Alt-S: cycle sort (current: $SORT_BY) | ↑/↓: navigate | Enter: resume | ?: toggle preview" \
    --bind "?:toggle-preview" \
    --bind "alt-s:reload(bash '${cycle_script}')" \
    "${fzf_flags[@]}" \
    2>/dev/null) || true

  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No session selected.${RESET}"
    exit 0
  fi

  # Extract session ID(s)
  local session_ids=()
  while IFS= read -r line; do
    local sid
    sid=$(echo "$line" | cut -f1)
    session_ids+=("$sid")
  done <<<"$selected"

  if [[ "$MODE" == "copy" ]]; then
    local copy_text
    copy_text=$(printf '%s\n' "${session_ids[@]}")
    if command -v xclip &>/dev/null; then
      echo "$copy_text" | xclip -selection clipboard
    elif command -v pbcopy &>/dev/null; then
      echo "$copy_text" | pbcopy
    elif command -v wl-copy &>/dev/null; then
      echo "$copy_text" | wl-copy
    else
      echo -e "${YELLOW}Session IDs:${RESET}"
      echo "$copy_text"
      echo -e "${DIM}(No clipboard tool found, copy manually)${RESET}"
    fi
    echo -e "${GREEN}Copied ${#session_ids[@]} session ID(s) to clipboard${RESET}"
    exit 0
  fi

  # Resume the first selected session with tmux session handling
  handle_session "${session_ids[0]}"
}

# ─── Handle tmux session creation/switching ─────────────────────────────────

handle_session() {
  local session_id="$1"

  # Get session directory from database
  local directory
  directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session WHERE id = '${session_id}';")

  if [[ -z "$directory" ]]; then
    echo -e "${RED}Error: Could not find directory for session ${session_id}${RESET}"
    exit 1
  fi

  if [[ ! -d "$directory" ]]; then
    echo -e "${RED}Error: Directory does not exist: ${directory}${RESET}"
    exit 1
  fi

  # Derive tmux session name from directory
  local session_name
  session_name=$(derive_repo_name "$directory")

  # Check if prefix should be used (default: false)
  local use_prefix
  use_prefix=$(get_tmux_option "@opencode-sessions-prefix" "false")
  if [[ "$use_prefix" != "false" ]]; then
    session_name="${use_prefix}${session_name}"
  fi

  echo -e "${GREEN}Resuming session: ${session_id}${RESET}"
  echo -e "${DIM}Directory: ${directory}${RESET}"
  echo -e "${DIM}Tmux session: ${session_name}${RESET}"

  # Check if tmux session already exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    # Session exists - create new window instead of switching
    echo -e "${DIM}Creating new window in existing tmux session${RESET}"
    tmux new-window -t "$session_name" -c "$directory" -n "opencode" "exec opencode -s ${session_id}"
    tmux switch-client -t "$session_name"
  else
    # Create new tmux session and run resume directly
    echo -e "${DIM}Creating new tmux session${RESET}"
    tmux new-session -d -s "$session_name" -c "$directory" "exec opencode -s ${session_id}"
    tmux switch-client -t "$session_name"
  fi
}

# ─── Main entry point ─────────────────────────────────────────────────────────

case "$MODE" in
list)
  run_list
  ;;
interactive | copy | multi)
  run_interactive
  ;;
esac
