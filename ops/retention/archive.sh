#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps
ensure_session_file

repo=""
job_id=""

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	--job)
		job_id="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
out_repo="$DOCKYARD_ROOT/out/$repo"
archive_repo="$DOCKYARD_ROOT/archive/$repo"
ensure_dir "$archive_repo"

archive_one() {
	local job="$1"
	local src="$out_repo/$job"
	[[ -d "$src" ]] || return 0
	local dst="$archive_repo/$job.tar.gz"
	if [[ -f "$dst" ]]; then
		log_info "Archive already exists: $dst"
		return 0
	fi
	tar -C "$out_repo" -czf "$dst" "$job"
	log_info "Archived: $dst"
}

if [[ -n "$job_id" ]]; then
	archive_one "$job_id"
	exit 0
fi

archive_after_days="$(yq e '.retention.archive_after_days // 14' "$DOCKYARD_ROOT/state/session.yaml")"
[[ -d "$out_repo" ]] || exit 0

while IFS= read -r path; do
	[[ -z "$path" ]] && continue
	age_days="$(days_since_mtime "$path")"
	if [[ "$age_days" -ge "$archive_after_days" ]]; then
		archive_one "$(basename "$path")"
	fi
done < <(sorted_job_dirs "$repo")
