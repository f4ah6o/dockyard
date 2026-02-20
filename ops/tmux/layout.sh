#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_tmux

session="${1:-dockyard}"

tmux select-layout -t "$session:main" tiled >/dev/null 2>&1 || true
tmux select-layout -t "$session:run" tiled >/dev/null 2>&1 || true
