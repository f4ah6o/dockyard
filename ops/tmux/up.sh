#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps
require_tmux

repo="${1:-}"
[[ -n "$repo" ]] || die "Usage: dock up <repo> [--runners N] [--attach stateless|resident|none]"
shift || true

runners=1
attach_mode="stateless"

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--runners)
		runners="${2:-}"
		shift 2
		;;
	--attach)
		attach_mode="${2:-}"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

[[ -d "$DOCKYARD_ROOT/repos/$repo/.git" ]] || die "Missing baseline repo: repos/$repo"
"$DOCKYARD_ROOT/ops/work/worktree-create.sh" "$repo" "$runners"

session="dockyard"
if tmux has-session -t "$session" 2>/dev/null; then
	tmux kill-session -t "$session"
fi

tmux new-session -d -s "$session" -n main -c "$DOCKYARD_ROOT"
tmux split-window -t "$session:main" -h -c "$DOCKYARD_ROOT"
tmux split-window -t "$session:main" -v -c "$DOCKYARD_ROOT"

tmux new-window -t "$session" -n run -c "$DOCKYARD_ROOT/worktrees/$repo/run-1"
for ((i = 2; i <= runners; i++)); do
	tmux split-window -t "$session:run" -h -c "$DOCKYARD_ROOT/worktrees/$repo/run-$i"
done

"$SCRIPT_DIR/layout.sh" "$session"

if [[ "$attach_mode" == "resident" ]]; then
	load_agents_env
	[[ -n "${ATTACH_ORCH_CMD:-}" ]] && tmux send-keys -t "$session:main.0" "$ATTACH_ORCH_CMD" C-m
	[[ -n "${ATTACH_STRATEGIST_CMD:-}" ]] && tmux send-keys -t "$session:main.1" "$ATTACH_STRATEGIST_CMD" C-m
	[[ -n "${ATTACH_REVIEWER_CMD:-}" ]] && tmux send-keys -t "$session:main.2" "$ATTACH_REVIEWER_CMD" C-m
	for ((i = 1; i <= runners; i++)); do
		pane=$((i - 1))
		[[ -n "${ATTACH_RUNNER_CMD:-}" ]] && tmux send-keys -t "$session:run.$pane" "$ATTACH_RUNNER_CMD" C-m
	done
fi

log_info "tmux session created: $session (attach mode: $attach_mode)"
