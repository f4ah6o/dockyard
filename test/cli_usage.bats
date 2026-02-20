#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	cd "$REPO_ROOT"
}

@test "dock prints usage when command is missing" {
	run ./dock
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage:"* ]]
}
