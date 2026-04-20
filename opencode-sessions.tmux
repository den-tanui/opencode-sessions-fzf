#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.
#
# Keybinding behavior:
#   Prefix+Z (or custom key) - Open sessions in popup
#   Alt+D in fzf - Toggle between sessions and directories view

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read options with defaults (using tmux commands like working plugins)
OPENCODE_DAYS="$(tmux show-option -gqv @opencode-sessions-days)"
[ -z "$OPENCODE_DAYS" ] && OPENCODE_DAYS="7"

OPENCODE_KEY="$(tmux show-option -gqv @opencode-sessions-key)"
[ -z "$OPENCODE_KEY" ] && OPENCODE_KEY="z"

OPENCODE_HEIGHT="$(tmux show-option -gqv @opencode-sessions-popup-height)"
[ -z "$OPENCODE_HEIGHT" ] && OPENCODE_HEIGHT="80%"

OPENCODE_WIDTH="$(tmux show-option -gqv @opencode-sessions-popup-width)"
[ -z "$OPENCODE_WIDTH" ] && OPENCODE_WIDTH="80%"

OPENCODE_BORDER="$(tmux show-option -gqv @opencode-sessions-popup-border)"
[ -z "$OPENCODE_BORDER" ] && OPENCODE_BORDER="false"

# FZF options
OPENCODE_FZF_OPTS="$(tmux show-option -gqv @opencode-sessions-fzf-opts)"
[ -z "$OPENCODE_FZF_OPTS" ] && OPENCODE_FZF_OPTS="--height 80% --ansi --layout=reverse"

# Build the command with options
OPENCODE_CMD="${CURRENT_DIR}/bin/opencode_sessions.sh --tmux"
OPENCODE_CMD="$OPENCODE_CMD --width '$OPENCODE_WIDTH'"
OPENCODE_CMD="$OPENCODE_CMD --height '$OPENCODE_HEIGHT'"
OPENCODE_CMD="$OPENCODE_CMD --days '$OPENCODE_DAYS'"
[ "$OPENCODE_BORDER" = "true" ] && OPENCODE_CMD="$OPENCODE_CMD --border"

# Bind the key (using tmux bind-key command)
tmux bind-key -n "$OPENCODE_KEY" run-shell -b "$OPENCODE_CMD"
