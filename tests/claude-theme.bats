#!/usr/bin/env bats

THEME="$BATS_TEST_DIRNAME/../home/dot_claude/themes/catppuccin-mocha.json"

@test "claude theme is valid JSON on a built-in base" {
  run jq -e '.base == "dark" and (.overrides | type == "object")' "$THEME"
  [ "$status" -eq 0 ]
}

@test "inline code and commands use a high-contrast colour" {
  # Claude Code paints inline code and unlabelled code blocks with the permission token.
  [ "$(jq -r '.overrides.permission' "$THEME")" = "#fab387" ]
}

@test "every override is a #rrggbb colour" {
  run jq -e '[.overrides[] | test("^#[0-9a-f]{6}$")] | all' "$THEME"
  [ "$status" -eq 0 ]
}
