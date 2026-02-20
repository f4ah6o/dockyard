#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_flock

if [[ "$#" -lt 1 ]]; then
	die "Usage: ops/lib/lock.sh <command> [args...]"
fi

session_lock_fd_open
"$@"
