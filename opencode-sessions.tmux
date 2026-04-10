#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default options
set -g @opencode-sessions-days "7"
set -g @opencode-sessions-sort "time"
set -g @opencode-sessions-prefix "false"
set -g @opencode-sessions-popup-height "80%"
set -g @opencode-sessions-popup-width "80%"
set -g @opencode-sessions-key "o"
set -g @opencode-sessions-popup-border "false"

# FZF options - passed as single string
set -g @opencode-sessions-fzf-opts "--height 80% --ansi --layout=reverse"

# Key binding - reads options from tmux at runtime
# Uses -n for no-prefix binding, -B to remove border if configured
bind-key -n "#{@opencode-sessions-key}" run-shell -b "tmux display-popup #{?@opencode-sessions-popup-border,-B,} -w '#{@opencode-sessions-popup-width}' -h '#{@opencode-sessions-popup-height}' -xC -yC -E ${CURRENT_DIR}/bin/opencode_sessions.sh"

