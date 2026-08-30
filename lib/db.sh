#!/usr/bin/env bash
# Database queries for opencode-sessions
# Optimized version - minimal fields returned, preview fetches extra data

# Relative time expression - expects a subquery alias with time_updated (ms) and diff (sec)
# < 1 min: "N sec ago" | < 1 hour: "N min ago" | < 1 day: "N hour(s) ago"
# < 1 week: "N day(s) ago" | older: "YYYY-MM-DD"
_sql_relative_time_case() {
	cat <<'SQL'
CASE
  WHEN q.diff < 60 THEN MAX(q.diff, 0) || ' sec ago'
  WHEN q.diff < 3600 THEN (q.diff / 60) || ' min ago'
  WHEN q.diff < 86400 THEN (q.diff / 3600) || ' hour' || CASE WHEN (q.diff / 3600) = 1 THEN '' ELSE 's' END || ' ago'
  WHEN q.diff < 604800 THEN (q.diff / 86400) || ' day' || CASE WHEN (q.diff / 86400) = 1 THEN '' ELSE 's' END || ' ago'
  ELSE strftime('%Y-%m-%d', q.time_updated / 1000, 'unixepoch', 'localtime')
END
SQL
}

# Query all sessions - returns minimal pipe-delimited fields for listing
# Args: db_path days_filter show_all dir_filter
# Returns: id|title|directory|time_updated|name|time_ago
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
SELECT q.id, q.title, q.directory, q.time_updated, q.name,
$(_sql_relative_time_case) AS time_ago
FROM (
  SELECT s.id, s.title, s.directory, s.time_updated, p.name,
         (CAST(strftime('%s','now') AS INTEGER) - s.time_updated / 1000) AS diff
  FROM session s
  JOIN project p ON s.project_id = p.id
  WHERE s.time_archived IS NULL
    AND s.parent_id IS NULL
    AND s.time_updated >= $time_threshold
  $(if [[ -n "$dir_filter" ]]; then echo "AND s.directory = '${dir_filter}'"; fi)
) q
ORDER BY q.time_updated DESC;
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
# Returns: id|title|directory|time_updated|name|time_ago
query_dir_sessions() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local dir_filter="${2:-}"

	[[ -z "$dir_filter" ]] && return

	sqlite3 -separator '|' "$db_path" "
SELECT q.id, q.title, q.directory, q.time_updated, q.name,
$(_sql_relative_time_case) AS time_ago
FROM (
  SELECT s.id, s.title, s.directory, s.time_updated, p.name,
         (CAST(strftime('%s','now') AS INTEGER) - s.time_updated / 1000) AS diff
  FROM session s
  JOIN project p ON s.project_id = p.id
  WHERE s.time_archived IS NULL
    AND s.parent_id IS NULL
    AND s.directory = '${dir_filter}'
) q
ORDER BY q.time_updated DESC;
"
}
