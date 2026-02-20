#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps
ensure_session_file

repo=""
dry_run=0

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	--dry-run)
		dry_run=1
		shift
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"

session_file="$DOCKYARD_ROOT/state/session.yaml"
out_repo="$DOCKYARD_ROOT/out/$repo"
worktree_repo="$DOCKYARD_ROOT/worktrees/$repo"

keep_jobs="$(yq e '.retention.keep_jobs // 50' "$session_file")"
delete_after_days="$(yq e '.retention.delete_after_days // 90' "$session_file")"
prune_after_days="$(yq e '.worktrees.prune_after_days // 30' "$session_file")"

if [[ -d "$out_repo" ]]; then
	mapfile -t jobs < <(sorted_job_dirs "$repo")
	total_jobs="${#jobs[@]}"
	overflow=0
	if [[ "$total_jobs" -gt "$keep_jobs" ]]; then
		overflow=$((total_jobs - keep_jobs))
	fi

	for idx in "${!jobs[@]}"; do
		job_path="${jobs[$idx]}"
		job_name="$(basename "$job_path")"
		age_days="$(days_since_mtime "$job_path")"
		remove=0

		if [[ "$idx" -lt "$overflow" ]]; then
			remove=1
		fi
		if [[ "$age_days" -ge "$delete_after_days" ]]; then
			remove=1
		fi

		if [[ "$remove" -eq 1 ]]; then
			if [[ "$dry_run" -eq 1 ]]; then
				echo "DRY-RUN remove job: out/$repo/$job_name (age=${age_days}d)"
			else
				rm -rf "$job_path"
				log_info "Removed job: out/$repo/$job_name"
			fi
		fi
	done
fi

if [[ -d "$worktree_repo" ]]; then
	while IFS= read -r wt; do
		[[ -z "$wt" ]] && continue
		age_days="$(days_since_mtime "$wt")"
		if [[ "$age_days" -ge "$prune_after_days" ]]; then
			if [[ "$dry_run" -eq 1 ]]; then
				echo "DRY-RUN remove worktree: ${wt#"$DOCKYARD_ROOT"/} (age=${age_days}d)"
			else
				rm -rf "$wt"
				log_info "Removed worktree: ${wt#"$DOCKYARD_ROOT"/}"
			fi
		fi
	done < <(find "$worktree_repo" -mindepth 1 -maxdepth 1 -type d -print | sort)
fi
