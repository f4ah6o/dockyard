#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_tmux

role="${1:-}"
command_text="${2:-}"

[[ -n "$role" && -n "$command_text" ]] || die "Usage: dock send <role> \"<command>\""

session="dockyard"

target=""
case "$role" in
orch)
	target="$session:main.0"
	;;
strat)
	target="$session:main.1"
	;;
review)
	target="$session:main.2"
	;;
run-*)
	idx="${role#run-}"
	pane=$((idx - 1))
	target="$session:run.$pane"
	;;
*)
	die "Unknown role: $role"
	;;
esac

tmux send-keys -t "$target" "$command_text" C-m
log_info "Sent command to $role"
