---
name: codify
description: Use when the user runs {{ .invoke }}codify, says they changed their terminal/editor config or installed a tool by hand, or a session-start line reports "changes not codified". Records local config changes into the dotfiles repo (~/Development/dotfiles) safely.
---

# Codify local changes into the dotfiles repo

Shared by Claude Code and Codex; the source is `home/.chezmoitemplates/skills/codify.md` in ~/Development/dotfiles.

Repo: `~/Development/dotfiles` (chezmoi source, `.chezmoiroot` = `home`). Run every command against that path; never `cd` the user's shell elsewhere for good.

1. Run `~/Development/dotfiles/bin/drift`. If it prints nothing, say "nothing to codify" and stop.

2. Show the findings grouped by kind in one short table (kind, target, what keeping it means). For `edited` findings, include the relevant lines of `chezmoi diff ~/<target>`; that diff runs repo → machine, so read it in reverse. Ask once which findings to **keep** (record in repo), **revert** (`chezmoi apply ~/<target>` overwrites the local change), or **skip** (leave as is).

3. Apply each kept finding:
   - `edited`: `chezmoi re-add ~/<target>`.
   - `untracked-config`: `chezmoi add ~/<target>`.
   - `pkg-extra`: append `brew "<name>"` or `cask "<name>"` to `Brewfile` in its section. Run `brew info --cask <name>` to tell which. For a **skipped** package, append its name to `lib/drift-ignore.txt` so it stops being reported.
   - `pkg-missing`: keep means `brew bundle --file=~/Development/dotfiles/Brewfile`; revert means delete its Brewfile line.
   - `owned-key`: change the repo's source of that key, never the live file: `lib/claude-hooks.fragment.json` for Claude hooks, `lib/codex-owned-keys.txt` for Codex settings, `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh` for git keys. Then run `chezmoi apply`.

4. Refuse anything matching a glob in `lib/denylist.txt` (settings.json, .zshrc, .gitconfig, Codex's auth.json and config.toml, ...). Those files can hold secrets. Offer instead to own only the specific key through a `run_onchange_after_` patch script, following `run_onchange_after_20-gitconfig.sh` as the pattern.

5. If `CUSTOMIZE.md` does not yet show the kind of setting that changed, add a one-line example under that tool's section.

6. Verify, from the repo: run `bats tests/`. Then stage only the paths this run changed, never `git add -A`, because the repo may hold unrelated work: `git add -- <each path you changed>`. Check `git status --short` shows nothing else staged, then scan exactly what will be committed: `gitleaks git --pre-commit --staged --redact --no-banner --config .gitleaks.toml`. If any step fails, stop and report the failure.

7. Commit with `chore(codify): <what changed>` and show the commit. Push only if the user says so.

8. Run `bin/drift` once more and confirm it prints nothing, or only the findings the user chose to skip.
