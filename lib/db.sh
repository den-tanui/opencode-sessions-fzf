#!/usr/bin/env bash
# Database queries for opencode-sessions
# Optimized version - minimal fields returned, preview fetches extra data

# Query all sessions - returns minimal pipe-delimited fields for listing
# Args: db_path days_filter show_all dir_filter
# Returns: id|title|directory|time_updated|name
query_all_sessions() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local days_filter="${2:-14}"
	local show_all="${3:-false}"
	local dir_filter="${4:-}"

	local time_threshold
	if [[ "$show_all" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - days_filter * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$db_path" "
SELECT s.id, s.title, s.directory, s.time_updated, p.name
FROM session s
JOIN project p ON s.project_id = p.id
WHERE s.time_archived IS NULL 
  AND s.parent_id IS NULL
  AND s.time_updated >= $time_threshold
$(if [[ -n "$dir_filter" ]]; then echo "AND s.directory = '${dir_filter}'"; fi)
ORDER BY s.time_updated DESC;
"
}

# Query unique directories - for directory filter toggle
# Args: db_path days_filter show_all
query_directories() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local days_filter="${2:-14}"
	local show_all="${3:-false}"

	local time_threshold
	if [[ "$show_all" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - days_filter * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$db_path" "
SELECT DISTINCT s.directory, COUNT(*) as cnt, MAX(s.time_updated) as latest
FROM session s
WHERE s.time_archived IS NULL 
  AND s.parent_id IS NULL
  AND s.time_updated >= $time_threshold
GROUP BY s.directory
ORDER BY latest DESC;
"
}

# Get session count
get_total_count() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	sqlite3 "$db_path" "SELECT COUNT(*) FROM session WHERE time_archived IS NULL AND parent_id IS NULL;"
}

# Query ALL unique directories (no time filter) - for --directories flag
# Args: db_path
# Returns: directory|count
query_all_directories() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	sqlite3 -separator '|' "$db_path" "
SELECT DISTINCT s.directory, COUNT(*) as cnt
FROM session s
WHERE s.time_archived IS NULL 
  AND s.parent_id IS NULL
GROUP BY s.directory
ORDER BY cnt DESC;
"
}

# Query sessions for a specific directory - returns ALL (no time filter)
# Args: db_path directory
# Returns: id|title|directory|time_updated|name
query_dir_sessions() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local dir_filter="${2:-}"

	[[ -z "$dir_filter" ]] && return

	sqlite3 -separator '|' "$db_path" "
SELECT s.id, s.title, s.directory, s.time_updated, p.name
FROM session s
JOIN project p ON s.project_id = p.id
WHERE s.time_archived IS NULL 
  AND s.parent_id IS NULL
  AND s.directory = '${dir_filter}'
ORDER BY s.time_updated DESC;
"
}
