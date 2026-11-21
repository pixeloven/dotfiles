#!/usr/bin/env bats
# lib/agent-plugins.sh against stub claude / codex / pi that record their argv in $TMP/calls and keep
# their state in the tool homes, plus the two chezmoi scripts that run it. The stubs model what the
# real tools were seen to do: Claude Code refuses `marketplace add` of a source its settings declare
# differently, records the marketplace commit as each plugin's gitCommitSha, and `marketplace remove`
# would uninstall everything; Codex records what its marketplace clone was fetched from.

REAL_REPO="$BATS_TEST_DIRNAME/.."
LIB="$REAL_REPO/lib/agent-plugins.sh"
SCRIPTS="$REAL_REPO/home/.chezmoiscripts"
NAMES="crew infra-skills planning-skills identity-skills language-skills"
PACKS="infra-skills planning-skills identity-skills language-skills"
REF="$(sed -nE 's/^@([^[:space:]]+).*/\1/p' "$REAL_REPO/lib/agent-plugins.txt" | head -n 1)"
LIVE_HOME="$HOME" LIVE_PATH="$PATH" # before setup() swaps them

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" CLAUDE_CONFIG_DIR="$TMP/claude" CODEX_HOME="$TMP/codex" PI_CODING_AGENT_DIR="$TMP/pi"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR/plugins" "$CODEX_HOME" "$PI_CODING_AGENT_DIR" "$TMP/stub" "$TMP/bin"
  # Only these tools and the system dirs, so the real CLIs on this machine are never reached.
  ln -s "$(command -v jq)" "$TMP/bin/jq"; ln -s "$(command -v git)" "$TMP/bin/git"
  ln -s "$(command -v chezmoi)" "$TMP/bin/chezmoi"
  export PATH="$TMP/stub:$TMP/bin:/usr/bin:/bin"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  echo '[]' > "$CLAUDE_CONFIG_DIR/claude-list.json"
  echo '{"plugins":{}}' > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  echo '{"installed":[]}' > "$CODEX_HOME/codex-list.json"
  echo '{"packages":[]}' > "$PI_CODING_AGENT_DIR/settings.json"

  cat > "$TMP/stub/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude $*" >> "$(dirname "$CLAUDE_CONFIG_DIR")/calls"
d="$CLAUDE_CONFIG_DIR" p="$CLAUDE_CONFIG_DIR/plugins"
clone() { # <repo> <ref> : (re)clone the marketplace; its one commit stands for <repo> at <ref>
  rm -rf "$p/marketplaces/pixeloven"; mkdir -p "$p/marketplaces/pixeloven"
  git -C "$p/marketplaces/pixeloven" init -q
  git -C "$p/marketplaces/pixeloven" commit -q --allow-empty -m "$1 $2"
  jq -n --arg r "$1" --arg ref "$2" --arg l "$p/marketplaces/pixeloven" \
    '{pixeloven: {source: ({source: "github", repo: $r} + (if $ref == "" then {} else {ref: $ref} end)), installLocation: $l}}' \
    > "$p/known_marketplaces.json"
}
head() { git -C "$p/marketplaces/pixeloven" rev-parse HEAD; }
record() { # <id> : the install record, at the marketplace's commit
  jq --arg id "$1" --arg s "$(head)" '.plugins[$id] = [{scope: "user", gitCommitSha: $s}]' "$p/installed_plugins.json" > "$d/t" &&
    mv "$d/t" "$p/installed_plugins.json"
}
case "$*" in
  "plugin list --json") cat "$d/claude-list.json" ;;
  "plugin marketplace add "*)
    [ ! -e "$d/offline" ] || exit 1
    src="$4"; repo="${src%%#*}"; ref=""; [ "$src" = "$repo" ] || ref="${src#*#}"
    want="$(jq -c --arg r "$repo" --arg ref "$ref" '{source: "github", repo: $r} + (if $ref == "" then {} else {ref: $ref} end)' -n)"
    have="$(jq -c '.extraKnownMarketplaces.pixeloven.source // empty' "$d/settings.json" 2>/dev/null)"
    [ -z "$have" ] || [ "$(jq -cS . <<<"$have")" = "$(jq -cS . <<<"$want")" ] ||
      { echo "source doesn't match its extraKnownMarketplaces entry" >&2; exit 1; }
    clone "$repo" "$ref" ;;
  "plugin marketplace update "*) [ ! -e "$d/offline" ] ;;
  "plugin marketplace remove "*) jq '.plugins = {}' "$p/installed_plugins.json" > "$d/t" && mv "$d/t" "$p/installed_plugins.json" ;;
  "plugin install "*)
    jq --arg id "$3" '. + [{id: $id, scope: "user", enabled: true}]' "$d/claude-list.json" > "$d/t" && mv "$d/t" "$d/claude-list.json"
    record "$3" ;;
  "plugin update "*) [ ! -e "$d/offline" ] && record "$3" ;;
esac
STUB
  cat > "$TMP/stub/codex" <<'STUB'
#!/usr/bin/env bash
echo "codex $*" >> "$(dirname "$CODEX_HOME")/calls"
d="$CODEX_HOME" m="$CODEX_HOME/.tmp/marketplaces/pixeloven"
get() { sed -n "/^\[marketplaces.pixeloven\]/,/^\[/s/^$1 = \"\(.*\)\"$/\1/p" "$d/config.toml"; }
fetch() { # clone the configured source at the configured ref and record it, as Codex does
  [ ! -e "$d/offline" ] || exit 1
  rm -rf "$m"; mkdir -p "$m"; git -C "$m" init -q; git -C "$m" commit -q --allow-empty -m "$(get source) $(get ref)"
  jq -n --arg s "$(get source)" --arg r "$(get ref)" --arg v "$(git -C "$m" rev-parse HEAD)" \
    '{source_type: "git", source: $s, ref_name: (if $r == "" then null else $r end), sparse_paths: [], revision: $v}' \
    > "$m/.codex-marketplace-install.json"
}
case "$*" in
  "plugin list --marketplace pixeloven --json") cat "$d/codex-list.json" ;;
  "plugin marketplace add "*)
    [ ! -e "$d/offline" ] || exit 1
    printf '\n[marketplaces.pixeloven]\nsource_type = "git"\nsource = "https://github.com/%s.git"\nref = "%s"\n' "$4" "$6" >> "$d/config.toml"
    fetch ;;
  "plugin marketplace upgrade "*) fetch ;;
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
[ "$1" != install ] || [ ! -e "$PI_CODING_AGENT_DIR/offline" ] || exit 1 # remove is local
# Like pi, a package's identity is its source without the ref: installing again replaces its entry in
# place and keeps an object entry's filters, and remove drops it.
id='(if type == "object" then .source else . end | split("@")[0])'
case "$1" in
  install) jq --arg src "$2" ".packages |= map(if $id == (\$src | split(\"@\")[0])
      then (if type == \"object\" then .source = \$src else \$src end) else . end)
    | if any(.packages[]; $id == (\$src | split(\"@\")[0])) then . else .packages += [\$src] end" "$s" > "$s.t" && mv "$s.t" "$s" ;;
  remove) jq --arg src "$2" ".packages |= map(select($id != (\$src | split(\"@\")[0])))" "$s" > "$s.t" && mv "$s.t" "$s" ;;
esac
exit 0
STUB
  chmod +x "$TMP/stub/claude" "$TMP/stub/codex" "$TMP/stub/pi"
}

teardown() { rm -rf "$TMP"; }

calls() { cat "$TMP/calls" 2>/dev/null; }
installs() { calls | grep -E "^(claude plugin (install|update)|codex plugin add|pi (install|remove)) " || true; }
moves() { calls | grep -E "(marketplace (add|update|upgrade|remove)|^pi (install|remove)) " || true; }
pi_packages() { jq -c '.packages' "$PI_CODING_AGENT_DIR/settings.json"; }

set_enabled() { # <name> <true|false> : flip a plugin installed in Claude Code and Codex
  jq --arg id "$1@pixeloven" --argjson e "$2" 'map(if .id == $id then .enabled = $e else . end)' \
    "$CLAUDE_CONFIG_DIR/claude-list.json" > "$TMP/t" && mv "$TMP/t" "$CLAUDE_CONFIG_DIR/claude-list.json"
  jq --arg n "$1" --argjson e "$2" '.installed |= map(if .name == $n then .enabled = $e else . end)' \
    "$CODEX_HOME/codex-list.json" > "$TMP/t" && mv "$TMP/t" "$CODEX_HOME/codex-list.json"
}

pinned_machine() { # every plugin installed at the pin through the tools themselves
  "$LIB" ensure 2>/dev/null
  rm -f "$TMP/calls"
}

old_machine() { # a machine set up from the pre-fold pixeloven/marketplace catalogue, everything enabled
  local p json='[]' sha
  jq -n '{model: "x", extraKnownMarketplaces: {pixeloven: {source: {source: "github", repo: "pixeloven/marketplace"}}, other: {source: {source: "github", repo: "o/r"}}}}' \
    > "$CLAUDE_CONFIG_DIR/settings.json"
  "$TMP/stub/claude" plugin marketplace add pixeloven/marketplace --json
  for p in $NAMES; do
    json="$(jq --arg id "$p@pixeloven" '. + [{id: $id, scope: "user", enabled: true}]' <<<"$json")"
    sha="$(printf 'a%.0s' $(seq 40))" # per-plugin catalogue SHAs, not the marketplace commit
    jq --arg id "$p@pixeloven" --arg s "$sha" '.plugins[$id] = [{scope: "user", gitCommitSha: $s}]' \
      "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$TMP/t" && mv "$TMP/t" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  done
  echo "$json" > "$CLAUDE_CONFIG_DIR/claude-list.json"
  printf '# mine\nmodel = "x"\n\n[marketplaces.pixeloven]\nsource_type = "git"\nsource = "https://github.com/pixeloven/marketplace.git"\n\n[tui]\ntheme = "t"\n' \
    > "$CODEX_HOME/config.toml"
  "$TMP/stub/codex" plugin marketplace upgrade pixeloven --json
  jq -n --arg names "$NAMES" '{installed: [$names | split(" ")[] | {name: ., installed: true, enabled: true, version: "1.0.0"}]}' \
    > "$CODEX_HOME/codex-list.json"
  jq -n --arg names "$NAMES" '{packages: (["npm:other"] + [$names | split(" ")[] | "git:github.com/pixeloven/\(.)@\("b" * 40)"])}' \
    > "$PI_CODING_AGENT_DIR/settings.json"
  rm -f "$TMP/calls"
}

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
  [ -z "$output" ]
}

@test "ensure pins a fresh machine to the crew release and installs every plugin" {
  [ -n "$REF" ]
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ "$(jq -c '.extraKnownMarketplaces.pixeloven.source' "$CLAUDE_CONFIG_DIR/settings.json")" = \
    "{\"source\":\"github\",\"repo\":\"pixeloven/crew\",\"ref\":\"$REF\"}" ]
  calls | grep -qxF "claude plugin marketplace add pixeloven/crew#$REF --json"
  calls | grep -qxF "codex plugin marketplace add pixeloven/crew --ref $REF --json"
  for p in $NAMES; do
    calls | grep -qxF "claude plugin install $p@pixeloven --scope user --json"
    calls | grep -qxF "codex plugin add $p@pixeloven --json"
  done
  calls | grep -qxF "pi install git:github.com/pixeloven/crew@$REF"
  [ "$(pi_packages)" = "[\"git:github.com/pixeloven/crew@$REF\"]" ] # one unfiltered package carries every pack
  [ "$(installs | wc -l | tr -d ' ')" -eq 11 ]
  [ -z "$(calls | grep -E 'marketplace (update|upgrade|remove)')" ] # a marketplace added just now is current
  run "$LIB" check
  [ "$status" -eq 0 ]; [ -z "$output" ]
  rm "$TMP/calls"
  run "$LIB" ensure # at the pin: nothing to do
  [ "$status" -eq 0 ]
  [ -z "$(moves)" ]; [ -z "$(installs)" ]
}

@test "ensure moves a pre-fold machine to the crew release, keeping everything else" {
  old_machine
  run "$LIB" check
  for p in $NAMES; do
    [[ "$output" == *$'plugin-behind\tclaude '"$p"$'@pixeloven\tnot at the pinned crew release '"$REF"'; run '*'/lib/agent-plugins.sh update'* ]] || false
    [[ "$output" == *$'plugin-behind\tcodex '"$p"'@pixeloven'* ]] || false
    [[ "$output" == *$'plugin-behind\tpi '"$p"'@pixeloven'* ]] || false
  done
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  # Claude Code: the declaration changes first (the stub's add refuses a mismatch), then the add, then updates.
  [ "$(jq -c '.extraKnownMarketplaces' "$CLAUDE_CONFIG_DIR/settings.json")" = \
    "{\"pixeloven\":{\"source\":{\"source\":\"github\",\"repo\":\"pixeloven/crew\",\"ref\":\"$REF\"}},\"other\":{\"source\":{\"source\":\"github\",\"repo\":\"o/r\"}}}" ]
  [ "$(jq -r .model "$CLAUDE_CONFIG_DIR/settings.json")" = x ]
  calls | grep -qxF "claude plugin marketplace add pixeloven/crew#$REF --json"
  [ -z "$(calls | grep 'marketplace remove')" ]
  for p in $NAMES; do
    calls | grep -A99 -xF "claude plugin marketplace add pixeloven/crew#$REF --json" | grep -qxF "claude plugin update $p@pixeloven --scope user --json"
  done
  [ -z "$(calls | grep -E '^claude plugin install ')" ]
  # Codex: the table is rewritten in place and the clone upgraded; installed plugins follow it.
  grep -qxF 'source = "https://github.com/pixeloven/crew.git"' "$CODEX_HOME/config.toml"
  grep -qxF "ref = \"$REF\"" "$CODEX_HOME/config.toml"
  [ -z "$(grep 'pixeloven/marketplace' "$CODEX_HOME/config.toml")" ]
  grep -qxF '# mine' "$CODEX_HOME/config.toml"; grep -qxF 'theme = "t"' "$CODEX_HOME/config.toml"
  [ "$(grep -c '^\[marketplaces.pixeloven\]' "$CODEX_HOME/config.toml")" -eq 1 ]
  calls | grep -qxF "codex plugin marketplace upgrade pixeloven --json"
  [ -z "$(calls | grep -E '^codex plugin (add|marketplace add) ')" ]
  # pi: one crew package at the tag replaces the five per-plugin ones; other packages stay.
  [ "$(pi_packages)" = "[\"npm:other\",\"git:github.com/pixeloven/crew@$REF\"]" ]
  for p in $PACKS; do calls | grep -qxF "pi remove git:github.com/pixeloven/$p@$(printf 'b%.0s' $(seq 40))"; done
  run "$LIB" check
  [ "$status" -eq 0 ]; [ -z "$output" ]
  rm "$TMP/calls"
  run "$LIB" ensure # idempotent
  [ "$status" -eq 0 ]
  [ -z "$(moves)" ]; [ -z "$(installs)" ]
}

@test "a pack turned off or filtered before the move is reported, and crew's package stays unfiltered" {
  old_machine
  set_enabled planning-skills false
  jq '.packages |= map(if test("/planning-skills@") then {source: ., skills: []} elif test("/identity-skills@") then {source: ., skills: ["skills/a"]} else . end)' \
    "$PI_CODING_AGENT_DIR/settings.json" > "$TMP/s" && mv "$TMP/s" "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ -z "$(calls | grep planning-skills | grep -E '^(claude|codex) ')" ]
  [ "$(jq '.[] | select(.id == "planning-skills@pixeloven") | .enabled' "$CLAUDE_CONFIG_DIR/claude-list.json")" = false ]
  [ "$(pi_packages)" = "[\"npm:other\",\"git:github.com/pixeloven/crew@$REF\"]" ]
  local quickstart="https://github.com/pixeloven/crew/blob/$REF/docs/quickstart-pi.md"
  for p in planning-skills identity-skills; do
    [[ "$output" == *"pi: $p was turned off or filtered; crew's package loads it now, filter packs/$p/ there: $quickstart"* ]] || false
  done
  for p in infra-skills language-skills; do [[ "$output" != *"pi: $p was turned off"* ]] || false; done
  run "$LIB" check
  [ -z "$output" ] # disabled plugins are never reported
}

@test "a failed move leaves the old setup working and is retried by the next ensure" {
  old_machine
  touch "$CLAUDE_CONFIG_DIR/offline" "$CODEX_HOME/offline" "$PI_CODING_AGENT_DIR/offline"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: claude plugin marketplace add pixeloven/crew#$REF --json"* ]] || false
  [[ "$output" == *"failed: codex plugin marketplace upgrade pixeloven --json"* ]] || false
  [[ "$output" == *"failed: pi install git:github.com/pixeloven/crew@$REF"* ]] || false
  [ -z "$(calls | grep -E '^claude plugin (update|install) ')" ] # nothing updated from a marketplace that didn't move
  [ "$(jq -r '.pixeloven.source.repo' "$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json")" = pixeloven/marketplace ]
  [ "$(jq '.plugins | length' "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json")" -eq 5 ]
  [ "$(jq '.packages | length' "$PI_CODING_AGENT_DIR/settings.json")" -eq 6 ] # no pack dropped before crew's package is in
  rm "$CLAUDE_CONFIG_DIR/offline" "$CODEX_HOME/offline" "$PI_CODING_AGENT_DIR/offline"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  run "$LIB" check
  [ -z "$output" ]
}

@test "ensure installs only the missing names" {
  pinned_machine
  jq 'map(select(.id != "language-skills@pixeloven"))' "$CLAUDE_CONFIG_DIR/claude-list.json" > "$TMP/t" && mv "$TMP/t" "$CLAUDE_CONFIG_DIR/claude-list.json"
  echo '{"packages":["npm:other"]}' > "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ -z "$(moves | grep marketplace)" ]
  [ "$(installs)" = "claude plugin install language-skills@pixeloven --scope user --json
pi install git:github.com/pixeloven/crew@$REF" ]
}

@test "ensure brings an enabled plugin that isn't at the pin up to it, and leaves a disabled one" {
  pinned_machine
  set_enabled planning-skills false
  jq '.plugins["crew@pixeloven"][0].gitCommitSha = "old" | .plugins["planning-skills@pixeloven"][0].gitCommitSha = "old"' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$TMP/i" && mv "$TMP/i" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  run "$LIB" ensure
  [ "$status" -eq 0 ]
  [ "$(installs)" = "claude plugin update crew@pixeloven --scope user --json" ]
}

@test "a failed install is reported and fails the run, after trying the rest" {
  printf '#!/bin/sh\necho "pi $*" >> "%s/calls"\nexit 1\n' "$TMP" > "$TMP/stub/pi"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed: pi install git:github.com/pixeloven/crew@$REF"* ]] || false
  [ "$(installs | grep -c '^claude ')" -eq 5 ]
  [ "$(installs | grep -c '^codex ')" -eq 5 ]
}

@test "a Claude settings file that isn't JSON is left alone, and so are Claude Code's plugins" {
  echo 'not json' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$LIB" ensure
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.json is not valid JSON"* ]] || false
  [ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = 'not json' ]
  [ -z "$(calls | grep -E '^claude plugin (marketplace|install|update)')" ]
}

@test "update refreshes every enabled plugin and leaves disabled ones alone" {
  pinned_machine
  set_enabled planning-skills false
  run "$LIB" update
  [ "$status" -eq 0 ]
  calls | grep -qxF "claude plugin marketplace update pixeloven --json"
  calls | grep -qxF "codex plugin marketplace upgrade pixeloven --json"
  for p in crew infra-skills identity-skills language-skills; do
    calls | grep -qxF "claude plugin update $p@pixeloven --scope user --json"
    calls | grep -qxF "codex plugin add $p@pixeloven --json"
  done
  [ -z "$(calls | grep 'planning-skills' | grep -E '^(claude|codex) ')" ]
  [ "$(jq '.installed[] | select(.name == "planning-skills") | .enabled' "$CODEX_HOME/codex-list.json")" = false ]
  [ -z "$(calls | grep -E '^pi ')" ] # crew's package is at the tag already
}

@test "update moves a pre-fold machine too" {
  old_machine
  run "$LIB" update
  [ "$status" -eq 0 ]
  run "$LIB" check
  [ -z "$output" ]
}

@test "update with nothing installed changes nothing" {
  run "$LIB" update
  [ "$status" -eq 0 ]
  [ -z "$(calls | grep -vE '^(claude plugin list|codex plugin list)')" ]
  [ ! -e "$CLAUDE_CONFIG_DIR/settings.json" ]
}

@test "check reports plugin-missing and plugin-behind, and never a disabled plugin" {
  pinned_machine
  set_enabled planning-skills false
  jq 'map(select(.id != "language-skills@pixeloven"))' "$CLAUDE_CONFIG_DIR/claude-list.json" > "$TMP/t" && mv "$TMP/t" "$CLAUDE_CONFIG_DIR/claude-list.json"
  jq '.plugins["crew@pixeloven"][0].gitCommitSha = "old" | .plugins["planning-skills@pixeloven"][0].gitCommitSha = "old"' \
    "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json" > "$TMP/i" && mv "$TMP/i" "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
  jq '.ref_name = "v0.0.1"' "$CODEX_HOME/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json" > "$TMP/m" &&
    mv "$TMP/m" "$CODEX_HOME/.tmp/marketplaces/pixeloven/.codex-marketplace-install.json"
  echo '{"packages":["git:github.com/pixeloven/crew@v0.0.1","git:github.com/pixeloven/infra-skills@abc"]}' > "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" check
  [ "$status" -eq 0 ]
  [[ "$output" == *$'plugin-missing\tclaude language-skills@pixeloven\tchezmoi apply'* ]] || false
  [[ "$output" == *$'plugin-behind\tclaude crew@pixeloven\tnot at the pinned crew release '* ]] || false
  [[ "$output" != *"claude planning-skills"* ]] || false # disabled
  [[ "$output" != *"claude infra-skills"* ]] || false    # at the pin
  for p in crew infra-skills identity-skills language-skills; do
    [[ "$output" == *$'plugin-behind\tcodex '"$p"'@pixeloven'* ]] || false # the clone isn't at the tag
  done
  [[ "$output" != *"codex planning-skills"* ]] || false # disabled
  [[ "$output" == *$'plugin-behind\tpi crew@pixeloven'* ]] || false
  [[ "$output" == *$'plugin-behind\tpi infra-skills@pixeloven'* ]] || false
  [ "$(wc -l <<<"$output" | tr -d ' ')" -eq 8 ]
  [ -z "$(installs)" ]; [ -z "$(moves)" ]
}

@test "check sees a marketplace on another ref as behind, and stays offline" {
  pinned_machine
  jq '.pixeloven.source.ref = "v0.0.1"' "$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json" > "$TMP/k" &&
    mv "$TMP/k" "$CLAUDE_CONFIG_DIR/plugins/known_marketplaces.json"
  sed -i.bak "s/^ref = .*/ref = \"v0.0.1\"/" "$CODEX_HOME/config.toml"
  echo '{"packages":[]}' > "$PI_CODING_AGENT_DIR/settings.json"
  run "$LIB" check
  [ "$status" -eq 0 ]
  [ "$(grep -c $'^plugin-behind\tclaude ' <<<"$output")" -eq 5 ]
  [ "$(grep -c $'^plugin-behind\tcodex ' <<<"$output")" -eq 5 ]
  [[ "$output" == *$'plugin-missing\tpi crew@pixeloven\tchezmoi apply'* ]] || false
  [ -z "$(calls | grep -vE '^(claude plugin list|codex plugin list)')" ]
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
