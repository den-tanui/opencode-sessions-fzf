#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.
#
# Keybinding behavior:
#   Prefix+o (or custom key) - Open sessions in popup
#   Alt+D in fzf - Toggle between sessions and directories view

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default options
set -g @opencode-sessions-days "7"
set -g @opencode-sessions-prefix "false"
set -g @opencode-sessions-popup-height "80%"
set -g @opencode-sessions-popup-width "80%"
set -g @opencode-sessions-key "o"
set -g @opencode-sessions-popup-border "false"

# FZF options - passed as single string
set -g @opencode-sessions-fzf-opts "--height 80% --ansi --layout=reverse"

# Key binding - uses --tmux flag so fzf handles popup directly
# Alt+D in fzf toggles between sessions and directories view
bind-key -n "#{@opencode-sessions-key}" run-shell -b "${CURRENT_DIR}/bin/opencode_sessions.sh --tmux --width '#{@opencode-sessions-popup-width}' --height '#{@opencode-sessions-popup-height}' --days '#{@opencode-sessions-days}'#{?@opencode-sessions-popup-border, --border,}"
