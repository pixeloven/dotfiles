#!/usr/bin/env bats
# lib/agent-plugins.sh against stub claude / codex / pi that record their argv in $TMP/calls and keep
# their state in the tool homes, plus the two chezmoi scripts that run it.

REAL_REPO="$BATS_TEST_DIRNAME/.."
LIB="$REAL_REPO/lib/agent-plugins.sh"
SCRIPTS="$REAL_REPO/home/.chezmoiscripts"
NAMES="crew infra-skills planning-skills identity-skills language-skills"
LIVE_HOME="$HOME" LIVE_PATH="$PATH" # before setup() swaps them

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/claude" CODEX_HOME="$TMP/codex" PI_CODING_AGENT_DIR="$TMP/pi"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/plugins" "$CODEX_HOME" "$PI_CODING_AGENT_DIR" "$TMP/stub" "$TMP/bin"
  # Only these tools and the system dirs, so the real CLIs on this machine are never reached.
  ln -s "$(command -v jq)" "$TMP/bin/jq"; ln -s "$(command -v git)" "$TMP/bin/git"
  ln -s "$(command -v chezmoi)" "$TMP/bin/chezmoi"
  export PATH="$TMP/stub:$TMP/bin:/usr/bin:/bin"
  export AGENT_PLUGINS_MARKETPLACE_URL="$TMP/none" # offline unless a test serves a catalogue
  export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  catalogue "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin" a
  echo '[]' > "$CLAUDE_CONFIG_DIR/claude-list.json"
  echo '[]' > "$CLAUDE_CONFIG_DIR/claude-mkt.json"
  echo '{"installed":[]}' > "$CODEX_HOME/codex-list.json"
  echo '{"marketplaces":[]}' > "$CODEX_HOME/codex-mkt.json"
  echo '{"packages":[]}' > "$PI_CODING_AGENT_DIR/settings.json"

  cat > "$TMP/stub/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$(dirname "$CLAUDE_CONFIG_DIR")/calls"
d="$CLAUDE_CONFIG_DIR"
case "$*" in
  "plugin list --json") cat "$d/claude-list.json" ;;
  "plugin marketplace list --json") cat "$d/claude-mkt.json" ;;
  "plugin marketplace add "*) echo '[{"name":"pixeloven"}]' > "$d/claude-mkt.json" ;;
  "plugin install "*)
    jq --arg id "$3" '. + [{id: $id, scope: "user", enabled: true}]' "$d/claude-list.json" > "$d/t" && mv "$d/t" "$d/claude-list.json" ;;
esac
STUB
  cat > "$TMP/stub/codex" <<'STUB'
#!/usr/bin/env bash
echo "codex $*" >> "$(dirname "$CODEX_HOME")/calls"
d="$CODEX_HOME"
case "$*" in
  "plugin list --marketplace pixeloven --json") cat "$d/codex-list.json" ;;
  "plugin marketplace list --json") cat "$d/codex-mkt.json" ;;
  "plugin marketplace add "*) echo '{"marketplaces":[{"name":"pixeloven"}]}' > "$d/codex-mkt.json" ;;
  "plugin add "*)
    n="${3%@*}"
    jq --arg n "$n" '.installed |= (map(select(.name != $n)) + [{name: $n, installed: true, enabled: true, version: "1.0.0"}])' \
      "$d/codex-list.json" > "$d/t" && mv "$d/t" "$d/codex-list.json" ;;
esac
STUB
  cat > "$TMP/stub/pi" <<'STUB'
#!/usr/bin/env bash
echo "pi $*" >> "$(dirname "$PI_CODING_AGENT_DIR")/calls"
s="$PI_CODING_AGENT_DIR/settings.json"
# Like pi, installing a package again replaces its entry in place and keeps an object entry's filters.
[ "$1" = install ] && jq --arg src "$2" '.packages |= map(
    if (if type == "object" then .source else . end | split("@")[0]) == ($src | split("@")[0])
    then (if type == "object" then .source = $src else $src end) else . end)
  | if any(.packages[]; (if type == "object" then .source else . end) == $src) then . else .packages += [$src] end' \
  "$s" > "$s.t" && mv "$s.t" "$s"
exit 0
STUB
  chmod +x "$TMP/stub/claude" "$TMP/stub/codex" "$TMP/stub/pi"
}

teardown() { rm -rf "$TMP"; }

catalogue() { # <dir> <letter> : write a marketplace catalogue pinning each name to <letter> repeated
  mkdir -p "$1"
  jq -n --arg l "$2" --arg names "$NAMES" \
    '{plugins: [$names | split(" ")[] | {name: ., source: {source: "url", url: "https://github.com/pixeloven/\(.).git", sha: ($l * 40)}}]}' \
    > "$1/marketplace.json"
}

sha() { printf "$1%.0s" $(seq 40); }
calls() { cat "$TMP/calls" 2>/dev/null; }
installs() { calls | grep -E "^(claude plugin install|codex plugin add|pi install) " || true; }

claude_has() { # <name> <enabled> ...
  local json='[]'
  while [ $# -gt 0 ]; do
    json="$(jq --arg id "$1@pixeloven" --argjson e "$2" '. + [{id: $id, scope: "user", enabled: $e}]' <<<"$json")"; shift 2
  done
  echo "$json" > "$CLAUDE_CONFIG_DIR/claude-list.json"
  echo '[{"name":"pixeloven"}]' > "$CLAUDE_CONFIG_DIR/claude-mkt.json"
}

codex_has() { # <name> <enabled> ...
  local json='{"installed":[]}'
  while [ $# -gt 0 ]; do
    json="$(jq --arg n "$1" --argjson e "$2" '.installed += [{name: $n, installed: true, enabled: $e, version: "1.0.0"}]' <<<"$json")"; shift 2
  done
  echo "$json" > "$CODEX_HOME/codex-list.json"
  echo '{"marketplaces":[{"name":"pixeloven"}]}' > "$CODEX_HOME/codex-mkt.json"
}

all_installed() { # every name present and enabled in all three tools, at catalogue letter <l>
  local p args=()
  for p in $NAMES; do args+=("$p" true); done
  claude_has "${args[@]}"
  codex_has "${args[@]}"
  jq -n --arg l "$1" --arg names "$NAMES" '{plugins: ($names | split(" ") | map({key: "\(.)@pixeloven", value: [{scope: "user", gitCommitSha: ($l * 40)}]}) | from_entries)}' \
    > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  for p in $NAMES; do
    git init -q "$CODEX_HOME/plugins/cache/pixeloven/$p/1.0.0"
    git -C "$CODEX_HOME/plugins/cache/pixeloven/$p/1.0.0" commit -q --allow-empty -m x
  done
  jq -n --arg l "$1" --arg names "$NAMES" '{packages: [$names | split(" ")[] | "git:github.com/pixeloven/\(.)@\($l * 40)"]}' \
    > "$PI_CODING_AGENT_DIR/settings.json"
}

codex_head() { git -C "$CODEX_HOME/plugins/cache/pixeloven/$1/1.0.0" rev-parse HEAD; }

@test "a tool that isn't installed is skipped" {
  rm "$TMP/stub/codex" "$TMP/stub/pi"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex not found; skipping"* ]] || false
  [[ "$output" == *"pi not found; skipping"* ]] || false
  [ "$(calls | grep -c '^claude plugin install ')" -eq 5 ]
  [ -z "$(calls | grep -E '^(codex|pi) ')" ]
  run "$LIB" check
  [ "$status" -eq 0 ]
  [ -z "$(grep -v $'\tclaude ' <<<"$output")" ]
}

@test "ensure adds the marketplace and every plugin to a fresh machine" {
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  calls | grep -qxF "claude plugin marketplace add pixeloven/marketplace --json"
  calls | grep -qxF "codex plugin marketplace add pixeloven/marketplace --json"
  for p in $NAMES; do
    calls | grep -qxF "claude plugin install $p@pixeloven --scope user --json"
    calls | grep -qxF "codex plugin add $p@pixeloven --json"
  done
  [ "$(installs | wc -l | tr -d ' ')" -eq 15 ]
}

@test "ensure installs only the missing names" {
  claude_has crew true infra-skills true planning-skills true identity-skills true
  codex_has crew true infra-skills true planning-skills true identity-skills true language-skills true
  jq '.packages = ["npm:other", "git:github.com/pixeloven/crew@abc"]' "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ -z "$(calls | grep 'marketplace add')" ]
  [ "$(installs | grep -c '^claude ')" -eq 1 ]
  calls | grep -qxF "claude plugin install language-skills@pixeloven --scope user --json"
  [ -z "$(installs | grep '^codex ')" ]
  [ "$(installs | grep -c '^pi ')" -eq 4 ]
  [ -z "$(installs | grep 'pixeloven/crew')" ]
  run "$LIB" ensure
  [ "$(installs | wc -l | tr -d ' ')" -eq 5 ]
}

@test "a disabled plugin is never re-installed" {
  claude_has crew true infra-skills true planning-skills false identity-skills true language-skills true
  codex_has crew true infra-skills true planning-skills false identity-skills true language-skills true
  all_names=""; for p in $NAMES; do all_names="$all_names\"git:github.com/pixeloven/$p@$(sha a)\","; done
  echo "{\"packages\":[${all_names%,}]}" | jq '.packages[2] = {source: .packages[2], skills: []}' > "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ -z "$(installs)" ]
  [ "$(jq '.[] | select(.id == "planning-skills@pixeloven") | .enabled' "$CLAUDE_CONFIG_DIR/claude-list.json")" = false ]
}

@test "pi installs each plugin at the catalogue's SHA" {
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  for p in $NAMES; do
    calls | grep -qxF "pi install git:github.com/pixeloven/$p@$(sha a)"
  done
  [ "$(jq -r '.packages[0]' "$PI_CODING_AGENT_DIR/settings.json")" = "git:github.com/pixeloven/crew@$(sha a)" ]
}

@test "pi pins to the fetched catalogue over a stale local copy, and to the local copy when offline" {
  catalogue "$TMP/market/.claude-plugin" b
  git -C "$TMP/market" init -q && git -C "$TMP/market" add -A && git -C "$TMP/market" commit -q -m x
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/market" run "$LIB" ensure
  [ "$status" -eq 0 ]
  for p in $NAMES; do calls | grep -qxF "pi install git:github.com/pixeloven/$p@$(sha b)"; done
  [ -z "$(installs | grep "^pi " | grep -v "@$(sha b)$")" ]
  echo '{"packages":[]}' > "$PI_CODING_AGENT_DIR/settings.json"; rm "$TMP/calls"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not fetch"*"using this machine's local catalogue copy"* ]] || false
  for p in $NAMES; do calls | grep -qxF "pi install git:github.com/pixeloven/$p@$(sha a)"; done
}

@test "pi fetches the catalogue when no tool has a copy" {
  rm -r "$CLAUDE_CONFIG_DIR/plugins/marketplaces" "$TMP/stub/claude" "$TMP/stub/codex"
  catalogue "$TMP/market/.claude-plugin" c
  git -C "$TMP/market" init -q && git -C "$TMP/market" add -A && git -C "$TMP/market" commit -q -m x
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/market" run "$LIB" ensure
  [ "$status" -eq 0 ]
  calls | grep -qxF "pi install git:github.com/pixeloven/crew@$(sha c)"
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/none" run "$LIB" ensure
  [ "$status" -eq 0 ] # nothing missing any more, so nothing is fetched
  echo '{"packages":[]}' > "$PI_CODING_AGENT_DIR/settings.json"
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/none" run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch"* ]] || false
}

@test "a failed install is reported and fails the run, after trying the rest" {
  printf '#!/bin/sh\necho "pi $*" >> "%s/calls"\nexit 1\n' "$TMP" > "$TMP/stub/pi"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: pi install git:github.com/pixeloven/crew@"* ]] || false
  [ "$(installs | grep -c '^pi ')" -eq 5 ]
  [ "$(installs | grep -c '^claude ')" -eq 5 ]
}

@test "update moves every enabled plugin to the new pins and leaves disabled ones alone" {
  all_installed a
  claude_has crew true infra-skills true planning-skills false identity-skills true language-skills true
  codex_has crew true infra-skills true planning-skills false identity-skills true language-skills true
  catalogue "$TMP/market/.claude-plugin" b
  git -C "$TMP/market" init -q && git -C "$TMP/market" add -A && git -C "$TMP/market" commit -q -m x
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/market" run "$LIB" update
  [ "$status" -eq 0 ]
  calls | grep -qxF "claude plugin marketplace update pixeloven --json"
  calls | grep -qxF "codex plugin marketplace upgrade pixeloven --json"
  calls | grep -qxF "claude plugin update crew@pixeloven --scope user --json"
  calls | grep -qxF "codex plugin add crew@pixeloven --json"
  [ -z "$(calls | grep 'planning-skills' | grep -E '^(claude|codex) ')" ]
  [ "$(jq '.installed[] | select(.name == "planning-skills") | .enabled' "$CODEX_HOME/codex-list.json")" = false ]
  for p in $NAMES; do calls | grep -qxF "pi install git:github.com/pixeloven/$p@$(sha b)"; done
  [ "$(jq -r '.packages | length' "$PI_CODING_AGENT_DIR/settings.json")" -eq 5 ]
  [ -z "$(jq -r '.packages[]' "$PI_CODING_AGENT_DIR/settings.json" | grep -v "@$(sha b)$")" ]
}

@test "update with nothing installed changes nothing" {
  catalogue "$TMP/market/.claude-plugin" b
  git -C "$TMP/market" init -q && git -C "$TMP/market" add -A && git -C "$TMP/market" commit -q -m x
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/market" run "$LIB" update
  [ "$status" -eq 0 ]
  [ -z "$(calls | grep -vE '^(claude plugin list|codex plugin list)')" ]
}

@test "check prints nothing when every tool is at the catalogue's pins" {
  all_installed a
  catalogue "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin" a
  for p in $NAMES; do # Codex's pin is its cache checkout's HEAD
    jq --arg n "$p" --arg s "$(codex_head "$p")" '(.plugins[] | select(.name == $n) | .source.sha) = $s' \
      "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json" > "$TMP/m" &&
      mv "$TMP/m" "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json"
  done
  jq --arg names "$NAMES" --slurpfile m "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json" \
    '.plugins |= with_entries(.key as $k | .value[0].gitCommitSha = ($m[0].plugins[] | select("\(.name)@pixeloven" == $k) | .source.sha))' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$TMP/i" && mv "$TMP/i" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  jq --slurpfile m "$CLAUDE_CONFIG_DIR/plugins/marketplaces/pixeloven/.claude-plugin/marketplace.json" \
    '.packages = [$m[0].plugins[] | "git:github.com/pixeloven/\(.name)@\(.source.sha)"]' \
    "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(installs)" ]
}

@test "check reports plugin-missing and plugin-behind, and never a disabled plugin" {
  all_installed a
  claude_has crew true infra-skills true planning-skills false identity-skills true
  codex_has crew false infra-skills true planning-skills true identity-skills true language-skills true
  jq '.packages |= map(select(contains("/identity-skills@") | not))' "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  jq '.plugins["crew@pixeloven"][0].gitCommitSha = "old"' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$TMP/i" && mv "$TMP/i" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  jq '.packages |= map(sub("/infra-skills@.*"; "/infra-skills@old"))' "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  # Codex's cache checkouts are real commits, so none of them is at the catalogue's "aaa..." pin.
  run "$LIB" check
  [ "$status" -eq 0 ]
  [[ "$output" == *$'plugin-missing\tclaude language-skills@pixeloven\tchezmoi apply'* ]] || false
  [[ "$output" == *$'plugin-behind\tclaude crew@pixeloven\tinstalled differs from this machine\'s local catalogue copy; run '*'/lib/agent-plugins.sh update'* ]] || false
  [[ "$output" == *$'plugin-behind\tcodex planning-skills@pixeloven\t'* ]] || false
  [[ "$output" == *$'plugin-missing\tpi identity-skills@pixeloven\tchezmoi apply'* ]] || false
  [[ "$output" == *$'plugin-behind\tpi infra-skills@pixeloven\t'* ]] || false
  [[ "$output" != *"claude planning-skills"* ]] || false # disabled
  [[ "$output" != *"codex crew"* ]] || false              # disabled
  [[ "$output" != *"claude infra-skills"* ]] || false     # at its pin
  [ -z "$(installs)" ]
}

@test "check without any local catalogue reports only missing plugins and fetches nothing" {
  rm -r "$CLAUDE_CONFIG_DIR/plugins/marketplaces"
  all_installed a
  jq '.packages |= .[1:]' "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  AGENT_PLUGINS_MARKETPLACE_URL="$TMP/none" run "$LIB" check
  [ "$status" -eq 0 ]
  [ "$output" = $'plugin-missing\tpi crew@pixeloven\tchezmoi apply' ]
}

@test "the apply script runs ensure, and agentPlugins = false renders nothing" {
  render() { printf '%s\n' "$1" > "$TMP/chezmoi.toml"; chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template < "$2"; }
  run render '' "$SCRIPTS/run_after_60-agent-plugins.sh.tmpl"
  [ "$status" -eq 0 ]
  [[ "$output" == *'/lib/agent-plugins.sh" ensure'* ]] || false
  run render $'[data]\nagentPlugins = false' "$SCRIPTS/run_after_60-agent-plugins.sh.tmpl"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run render $'[data]\nagentPlugins = false\noperatorHome = "~/op"' "$SCRIPTS/run_onchange_after_61-operator-crew-fence.sh.tmpl"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "the operator fence runs only when operatorHome is set, and only through the home's po-crew.sh" {
  render() { printf '%s\n' "$1" > "$TMP/chezmoi.toml"; chezmoi --source "$REAL_REPO" --config "$TMP/chezmoi.toml" execute-template < "$SCRIPTS/run_onchange_after_61-operator-crew-fence.sh.tmpl"; }
  run render ''
  [ "$status" -eq 0 ]; [ -z "$output" ]
  mkdir -p "$HOME/op/bin"
  render $'[data]\noperatorHome = "~/op"' > "$TMP/fence.sh"
  grep -qxF "#   fence: absent" "$TMP/fence.sh"
  run sh "$TMP/fence.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *skipping* ]] || false
  printf '#!/bin/sh\necho "$*" > "%s/fenced"\n' "$TMP" > "$HOME/op/bin/po-crew.sh"; chmod +x "$HOME/op/bin/po-crew.sh"
  render $'[data]\noperatorHome = "~/op"' > "$TMP/fence.sh"
  grep -qxF "#   fence: present" "$TMP/fence.sh"
  run sh "$TMP/fence.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/fenced")" = "fence $HOME/op" ]
}

# bats test_tags=machine
@test "check runs on this machine's live install" {
  unset CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR
  HOME="$LIVE_HOME" PATH="$LIVE_PATH" run "$LIB" check
  [ "$status" -eq 0 ]
  [ -z "$(grep -vE $'^plugin-(missing|behind)\t(claude|codex|pi) [a-z-]+@pixeloven\t' <<<"$output")" ]
}
