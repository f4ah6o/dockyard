#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	cd "$REPO_ROOT"

	rm -rf repos/demo worktrees/demo out/demo archive/demo
	mkdir -p repos/demo

	git -C repos/demo init
	git -C repos/demo config user.email "dockyard@example.com"
	git -C repos/demo config user.name "Dockyard Test"
	echo "hello" >repos/demo/README.md
	git -C repos/demo add README.md
	git -C repos/demo commit -m "init"

	cp state/session.yaml.example state/session.yaml
	yq -i '.current_repo = "demo"' state/session.yaml
}

teardown() {
	rm -rf repos/demo worktrees/demo out/demo archive/demo
	rm -f state/session.yaml
}

@test "orchestrate --once creates core artifacts in mock mode" {
	run env DOCKYARD_MOCK_LLM=1 ./dock orchestrate --once --repo demo --runners 1
	[ "$status" -eq 0 ]

	latest_job="$(ls -1 out/demo | sort | tail -n 1)"
	[ -n "$latest_job" ]

	[ -f "out/demo/$latest_job/plan.yaml" ]
	[ -f "out/demo/$latest_job/review.yaml" ]
	[ -f "out/demo/$latest_job/decision.yaml" ]
	[ -f "out/demo/$latest_job/artifacts/diff.patch" ]
}
