#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."
MERGE="$REPO/lib/claude-settings-merge.sh"
FRAGMENT="$REPO/lib/claude-hooks.fragment.json"

setup() {
  TMP="$(mktemp -d)"
  SETTINGS="$TMP/settings.json"
  cp "$BATS_TEST_DIRNAME/fixtures/settings.existing.json" "$SETTINGS"
}

teardown() { rm -rf "$TMP"; }

@test "merge adds Stop and Notification hooks" {
  run "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.Stop | length' "$SETTINGS")" -eq 1 ]
  [[ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$SETTINGS")" == *"speak-alert.sh stop"* ]] || false
  [[ "$(jq -r '.hooks.Notification[0].hooks[0].command' "$SETTINGS")" == *"speak-alert.sh notify"* ]] || false
}

@test "merge preserves existing SessionStart hooks and unrelated keys" {
  "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | test("axi|herdr"))] | length' "$SETTINGS")" -eq 4 ]
  [ "$(jq -r '.model' "$SETTINGS")" = "example-model" ]
  [ "$(jq -c '.enabledPlugins' "$SETTINGS")" = '{"example@market":true}' ]
  [ "$(jq -r '.effortLevel' "$SETTINGS")" = "high" ]
}

@test "merge is idempotent" {
  "$MERGE" "$SETTINGS" "$FRAGMENT"
  cp "$SETTINGS" "$TMP/first.json"
  backups_before="$(ls "$TMP" | grep -c '\.bak-' || true)"
  run "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$status" -eq 0 ]
  cmp "$SETTINGS" "$TMP/first.json"
  [ "$(ls "$TMP" | grep -c '\.bak-' || true)" -eq "$backups_before" ]
}

@test "merge backs up before first write" {
  "$MERGE" "$SETTINGS" "$FRAGMENT"
  backup="$(ls "$TMP"/settings.json.bak-* | head -1)"
  cmp "$backup" "$BATS_TEST_DIRNAME/fixtures/settings.existing.json"
}

@test "merge creates settings when absent" {
  rm "$SETTINGS"
  run "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$status" -eq 0 ]
  [ "$(jq -c 'keys' "$SETTINGS")" = '["hooks"]' ]
}

@test "merge refuses invalid JSON without writing" {
  printf '{ not json' > "$SETTINGS"
  run "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$status" -eq 2 ]
  [ "$(cat "$SETTINGS")" = '{ not json' ]
  [ -z "$(ls "$TMP" | grep '\.bak-' || true)" ]
}

@test "merge adds the drift notice to SessionStart" {
  "$MERGE" "$SETTINGS" "$FRAGMENT"
  [ "$(jq '.hooks.SessionStart | length' "$SETTINGS")" -eq 5 ]
  [[ "$(jq -r '.hooks.SessionStart[4].hooks[0].command' "$SETTINGS")" == *"bin/drift --hook"* ]] || false
}

@test "merge removes hooks dropped from the fragment" {
  APPLIED="$TMP/applied.json"
  jq '.hooks.Stop[0].hooks[0].command = "old-stop-command"' "$FRAGMENT" > "$TMP/old-fragment.json"
  "$MERGE" "$SETTINGS" "$TMP/old-fragment.json" "$APPLIED"
  [ "$(jq '[.hooks.Stop[].hooks[].command] | index("old-stop-command")' "$SETTINGS")" = "0" ]
  "$MERGE" "$SETTINGS" "$FRAGMENT" "$APPLIED"
  [ "$(jq '[.hooks.Stop[].hooks[].command] | index("old-stop-command")' "$SETTINGS")" = "null" ]
  [ "$(jq '.hooks.Stop | length' "$SETTINGS")" -eq 1 ]
  [ "$(jq '[.hooks.SessionStart[] | select(.hooks[0].command | test("axi|herdr"))] | length' "$SETTINGS")" -eq 4 ]
}

@test "retiring a hook keeps other commands that share its group" {
  APPLIED="$TMP/applied.json"
  jq '.hooks.Stop[0].hooks[0].command = "old-stop-command"' "$FRAGMENT" > "$TMP/old-fragment.json"
  "$MERGE" "$SETTINGS" "$TMP/old-fragment.json" "$APPLIED"
  # The user adds their own command to the same group as ours.
  jq '(.hooks.Stop[] | select(.hooks[0].command == "old-stop-command") | .hooks) += [{"type":"command","command":"my-own-stop"}]' \
    "$SETTINGS" > "$TMP/s.json" && mv "$TMP/s.json" "$SETTINGS"
  "$MERGE" "$SETTINGS" "$FRAGMENT" "$APPLIED"
  [ "$(jq '[.hooks.Stop[].hooks[].command] | index("my-own-stop") != null' "$SETTINGS")" = "true" ]
  [ "$(jq '[.hooks.Stop[].hooks[].command] | index("old-stop-command")' "$SETTINGS")" = "null" ]
}
