#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Source install without running main(). install sets `set -e`; neutralize it
  # in the test shell so intentional non-zero assertions don't abort the test.
  source "$REPO/install"
  set +e
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
}

@test "merge preserves existing keys and adds hooks" {
  echo '{"model":"opus","theme":"dark"}' > "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  [ "$(jq -r '.model' "$SETTINGS")" = "opus" ]
  [ "$(jq -r '.theme' "$SETTINGS")" = "dark" ]
  [ "$(jq -r '.hooks.Stop[0].hooks[0].type' "$SETTINGS")" = "command" ]
  jq -e '.hooks.Notification' "$SETTINGS"
}

@test "merge is idempotent (no duplicate hook entries)" {
  echo '{}' > "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  [ "$(jq '.hooks.Stop | length' "$SETTINGS")" -eq 1 ]
  [ "$(jq '.hooks.Notification | length' "$SETTINGS")" -eq 1 ]
}

@test "merge creates file when absent" {
  rm -f "$SETTINGS"
  merge_claude_hooks "$SETTINGS"
  jq -e '.hooks.Stop' "$SETTINGS"
}

@test "cursor hooks written with gate and stop entries" {
  TARGET="$BATS_TEST_TMPDIR/hooks.json"
  write_cursor_hooks "$TARGET"
  jq -e '.hooks.beforeShellExecution[0].command' "$TARGET"
  jq -e '.hooks.stop[0].command' "$TARGET"
  [[ "$(jq -r '.hooks.stop[0].command' "$TARGET")" == *"|| true"* ]]
}
