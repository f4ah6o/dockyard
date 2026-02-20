#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_tmux

role="${1:-}"
out_file="${2:-}"

[[ -n "$role" && -n "$out_file" ]] || die "Usage: ops/tmux/capture.sh <role> <output-file>"

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

ensure_dir "$(dirname "$out_file")"
tmux capture-pane -p -t "$target" >"$out_file"
log_info "Captured $role pane -> $out_file"
