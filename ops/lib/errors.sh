#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"

append_error() {
	local errors_file="$1"
	local phase="$2"
	local actor="$3"
	local kind="$4"
	local detail="$5"
	local retry_count="${6:-0}"

	init_yaml_array_file "$errors_file" "errors"

	PHASE="$phase" \
		ACTOR="$actor" \
		KIND="$kind" \
		DETAIL="$detail" \
		RETRY_COUNT="$retry_count" \
		yq -i '.errors += [{
      "phase": strenv(PHASE),
      "actor": strenv(ACTOR),
      "kind": strenv(KIND),
      "detail": strenv(DETAIL),
      "retry_count": (strenv(RETRY_COUNT) | tonumber)
    }]' "$errors_file"
}
