#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	cd "$REPO_ROOT"
	TMP_DIR="$(mktemp -d)"
}

teardown() {
	rm -rf "$TMP_DIR"
}

@test "ensure_claude_settings_for_dir merges env keys without clobbering existing fields" {
	mkdir -p "$TMP_DIR/.claude"
	cat >"$TMP_DIR/.claude/settings.json" <<JSON
{
  "foo": "bar",
  "env": {
    "KEEP_ME": "yes"
  }
}
JSON

	run bash -lc "source ops/lib/common.sh; ZAI_API_KEY=test-key ensure_claude_settings_for_dir '$TMP_DIR'"
	[ "$status" -eq 0 ]

	[ "$(yq e -r '.foo' "$TMP_DIR/.claude/settings.json")" = "bar" ]
	[ "$(yq e -r '.env.KEEP_ME' "$TMP_DIR/.claude/settings.json")" = "yes" ]
	[ "$(yq e -r '.env.ANTHROPIC_AUTH_TOKEN' "$TMP_DIR/.claude/settings.json")" = "test-key" ]
	[ "$(yq e -r '.env.ANTHROPIC_BASE_URL' "$TMP_DIR/.claude/settings.json")" = "https://api.z.ai/api/anthropic" ]
	[ "$(yq e -r '.env.API_TIMEOUT_MS' "$TMP_DIR/.claude/settings.json")" = "3000000" ]
}

@test "ensure_claude_settings_for_dir fails when ZAI_API_KEY is missing" {
	run bash -lc "source ops/lib/common.sh; unset ZAI_API_KEY; ensure_claude_settings_for_dir '$TMP_DIR'"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Missing required env var: ZAI_API_KEY"* ]]
}
