#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps

if [[ "$#" -ne 1 ]]; then
	die "Usage: dock clone <git-url>"
fi

git_url="$1"
ensure_dir "$DOCKYARD_ROOT/repos"

repo_name="$(basename "$git_url")"
repo_name="${repo_name%.git}"
target_dir="$DOCKYARD_ROOT/repos/$repo_name"

if [[ -d "$target_dir/.git" ]]; then
	die "Repository already exists: repos/$repo_name"
fi

git clone "$git_url" "$target_dir"
log_info "Cloned $git_url -> repos/$repo_name"
