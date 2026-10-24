#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

setup() { TMP="$(mktemp -d)"; }
teardown() { rm -rf "$TMP"; }

@test "gitleaks path rule matches denylist" {
  while IFS= read -r glob; do
    case "$glob" in ''|'#'*) continue ;; esac
    name="${glob//\*/x}"
    rm -rf "${TMP:?}"/*
    mkdir -p "$(dirname "$TMP/$name")"
    echo harmless > "$TMP/$name"
    run gitleaks dir --no-banner --exit-code 3 --config "$REPO/.gitleaks.toml" "$TMP"
    [ "$status" -eq 3 ] || { echo "not blocked: $name"; false; }
  done < "$REPO/lib/denylist.txt"
}

@test "gitleaks allows ordinary config files" {
  echo 'theme = x' > "$TMP/config.ghostty"
  run gitleaks dir --no-banner --exit-code 3 --config "$REPO/.gitleaks.toml" "$TMP"
  [ "$status" -eq 0 ]
}

@test "gitleaks catches a token in an allowed file" {
  # Random each run so the fake token never lives in the repo as a fixed string.
  echo "GITHUB_TOKEN=ghp_$(head -c 4096 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 36)" > "$TMP/env.sh"
  run gitleaks dir --no-banner --exit-code 3 --config "$REPO/.gitleaks.toml" "$TMP"
  [ "$status" -eq 3 ]
}

@test "gitleaks blocks Codex's login and config files" {
  for f in .codex/auth.json .codex/config.toml dot_codex/config.toml private_dot_codex/config.toml.tmpl; do
    rm -rf "${TMP:?}"/* "$TMP"/.codex
    mkdir -p "$(dirname "$TMP/$f")"
    echo 'model = "x"' > "$TMP/$f"
    run gitleaks dir --no-banner --exit-code 3 --config "$REPO/.gitleaks.toml" "$TMP"
    [ "$status" -eq 3 ] || { echo "not blocked: $f"; false; }
  done
}

@test "gitleaks still allows herdr's config.toml" {
  mkdir -p "$TMP/dot_config/herdr"
  echo 'onboarding = false' > "$TMP/dot_config/herdr/config.toml"
  run gitleaks dir --no-banner --exit-code 3 --config "$REPO/.gitleaks.toml" "$TMP"
  [ "$status" -eq 0 ]
}
