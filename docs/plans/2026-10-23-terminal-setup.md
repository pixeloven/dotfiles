# Terminal Setup as Code Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A public, chezmoi-managed repo that rebuilds Brian's Ghostty + herdr + Claude Code terminal setup on any Mac with one command, without ever committing a file that can hold secrets.

**Architecture:** chezmoi owns files that are safe to publish in full (Ghostty, herdr, bat, glow configs and the speak-alert hook script). Files that can hold secrets or personal data (`~/.claude/settings.json`, `~/.gitconfig`) are never committed. Instead, idempotent `run_onchange_` scripts patch only the keys we own. A Brewfile installs packages. Anything that can't be automated goes in `RUNBOOK.md` as short numbered steps.

**Tech Stack:** chezmoi, Homebrew `brew bundle`, POSIX sh/bash, jq, bats-core, shellcheck, gitleaks, GitHub Actions (macos-latest).

**Spec:** The conversation decisions recorded in this section are the spec:
- Repo is public. Never commit any file that could contain sensitive data. Use automation to update such files, or easy manual steps where that isn't possible.
- Use the standard tooling: Brewfile + chezmoi. Don't overthink it. The setup must be easy to rebuild.
- Theme: Catppuccin, Mocha for dark and Latte for light, auto-switching with macOS, across Ghostty, herdr, bat, delta, and Claude Code.
- Voice: herdr agent sounds, Ghostty command-finish notifications, and a Claude Code hook that speaks a short line when an agent stops or needs attention. Dictation app setup is a runbook item. Local Whisper is out of scope.
- Rendering: a coding font, plus bat, delta, and glow. Trial herdr's `kitty_graphics` passthrough.
- Customization runbooks: for every tool, explain how to change it and how the change gets recorded.
- An easy-to-use skill that records manual changes (configs edited in place, packages installed by hand, owned keys changed in patched files) into the repo, so the setup can evolve without losing track of its state.
- Config as code = chezmoi + Brewfile. Nix/home-manager was considered and rejected as overkill.
- Scope is this Mac only. Linux, remote, and headless machines are deferred to a later onboarding (chezmoi supports them), so don't add OS templating now. *(Superseded 2026-10-24: the repo now supports macOS and Linux from one source tree. Per-OS files are chosen by `home/.chezmoiignore`, and Linux asks which terminal at `chezmoi init`.)*

## Global Constraints

- Repo path `~/Development/dotfiles`. chezmoi `sourceDir` points there. `.chezmoiroot` = `home`, so the repo root holds README, RUNBOOK, Brewfile, tests, and CI.
- GitHub repo `pixeloven/dotfiles`, **public**. Creating it is an outward-facing step: get the operator's explicit go-ahead first (Task 7).
- Never track `~/.claude/settings.json`, `~/.claude.json`, `~/.gitconfig`, `~/.zshrc`, `~/.ssh/*`, `~/.config/gh/*`, or any herdr runtime file (`*.sock`, `*.log`, `session.json`, `sessions/`, `release-notes.json`).
- Patch scripts change only the keys they own, back up the target file before the first write (`<file>.bak-YYYYmmddHHMMSS`), and must produce byte-identical output on a second run.
- Ghostty config target: `~/.config/ghostty/config.ghostty`. Leave the empty `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` untouched. Ghostty loads both files.
- Theme values: Ghostty `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`. herdr `[theme] name = "catppuccin"`, `auto_switch = true`, `dark_name = "catppuccin"`, `light_name = "catppuccin-latte"`.
- Font: `JetBrains Mono` (cask `font-jetbrains-mono`), size 14, with ligatures off (`font-feature = -calt`, `-liga`). Ghostty bundles the Nerd Font symbols, so no patched font is needed. CUSTOMIZE.md shows the one-line change to turn ligatures on.
- Speak hook must stay silent when `FM_TASK_ID` is set (fleet workers, since herdr sounds already cover them) or when `~/.config/speak-alert/muted` exists.
- Commits carry no agent co-author line.

## Review Focus

1. **Existing `settings.json` hooks:** the merge must keep the four existing SessionStart hooks (gh-axi, chrome-devtools-axi, lavish-axi, herdr-agent-state) and every non-hook key. Test: `merge preserves existing SessionStart hooks and unrelated keys`.
2. **Re-running `chezmoi apply`:** a second run must not duplicate hook entries or gitconfig values. Tests: `merge is idempotent`, `gitconfig script is idempotent`.
3. **Fleet noise:** five workers finishing at once must not speak five times. Test: `speak-alert is silent when FM_TASK_ID is set`.
4. **Missing or invalid `settings.json`** (fresh Mac, or a hand-broken file): create the file when it's absent. When it's invalid JSON, stop with a clear message and don't overwrite it. Tests: `merge creates settings when absent`, `merge refuses invalid JSON without writing`.
5. **Secrets slipping in through a later commit:** gitleaks runs in CI and as a pre-commit hook. Test: CI job `secrets` fails on a planted fake token (Task 6, Step 3).
6. **`/codify` pulling in a sensitive file:** if you ask it to start tracking `~/.claude/settings.json` or `~/.zshrc`, it must refuse and offer an owned-key patch instead. Test: `drift never proposes a denylisted path` (Task 8).

---

## File Structure

```
~/Development/dotfiles/
  .chezmoiroot                      # "home"
  Brewfile                          # packages (Task 1)
  README.md                         # one-command rebuild (Task 7)
  RUNBOOK.md                        # manual steps (Task 7)
  .gitleaks.toml  .githooks/pre-commit  .github/workflows/ci.yml   (Task 6)
  tests/  *.bats  fixtures/
  home/
    .chezmoi.toml.tmpl              # sourceDir, no personal data prompts
    .chezmoiignore
    .chezmoiscripts/
      run_onchange_before_00-brew-bundle.sh.tmpl         (Task 1)
      run_onchange_after_10-claude-settings.sh.tmpl      (Task 4)
      run_onchange_after_20-gitconfig.sh                 (Task 5)
    dot_config/ghostty/config.ghostty                    (Task 2)
    dot_config/herdr/config.toml                         (Task 3)
    dot_config/bat/config                                (Task 5)
    dot_config/glow/glow.yml                             (Task 5)
    dot_claude/hooks/executable_speak-alert.sh           (Task 4)
    private_dot_config/speak-alert/.keep                 (Task 4)
  lib/claude-settings-merge.sh      # pure jq merge, unit-tested (Task 4)
  lib/claude-hooks.fragment.json    # the hooks we own (Task 4)
  lib/denylist.txt                  # paths that are never tracked (Tasks 6, 8)
  bin/drift                         # drift report: files, packages, owned keys (Task 8)
  home/dot_claude/skills/codify/SKILL.md   # the /codify skill, itself versioned (Task 8)
  CUSTOMIZE.md                      # per-tool customization runbooks (Task 7)
```

---

### Task 1: Repo skeleton, chezmoi wiring, Brewfile

**Files:**
- Create: `.chezmoiroot`, `home/.chezmoi.toml.tmpl`, `home/.chezmoiignore`, `Brewfile`, `home/.chezmoiscripts/run_onchange_before_00-brew-bundle.sh.tmpl`, `tests/skeleton.bats`

**Interfaces:**
- Produces: the repo at `~/Development/dotfiles`, chezmoi configured with `sourceDir = "~/Development/dotfiles"`, and `brew bundle` running whenever the Brewfile hash changes.

- [ ] **Step 1: `git init`** in `~/Development/dotfiles`. The plan file already exists there.
- [ ] **Step 2: Write `tests/skeleton.bats`.** Test `chezmoi sees source root` asserts `chezmoi source-path` equals `$HOME/Development/dotfiles/home`. Test `brewfile parses` asserts `brew bundle list --file=Brewfile --all` exits 0 and its output contains `ghostty`, `font-jetbrains-mono`, `bat`, `git-delta`, `glow`, `chezmoi`.
- [ ] **Step 3: Run `bats tests/skeleton.bats`.** Expected: FAIL (no chezmoi, no Brewfile).
- [ ] **Step 4: Create the files.**
  - `Brewfile`:
    - Apps: `cask "ghostty"`, `cask "font-jetbrains-mono"`.
    - CLI: `brew "chezmoi"`, `brew "bat"`, `brew "git-delta"`, `brew "glow"`, `brew "jq"`.
    - Dev tools: `brew "bats-core"`, `brew "shellcheck"`, `brew "gitleaks"`.
  - herdr is **not** in the Brewfile because it installs itself into `~/.local/bin`. It goes in the runbook (Task 7).
  - `.chezmoiroot` contains `home`.
  - `home/.chezmoi.toml.tmpl` sets `sourceDir`. It has no `promptString`: there's no email or name, and that is deliberate.
  - The brew script embeds `{{ include "../Brewfile" | sha256sum }}` in a comment so it re-runs when the Brewfile changes, then runs `brew bundle --file="{{ .chezmoi.sourceDir }}/../Brewfile" --no-upgrade`.
- [ ] **Step 5: Install chezmoi and apply.** Run `brew install chezmoi && chezmoi init --source ~/Development/dotfiles && chezmoi apply -v`, then `bats tests/skeleton.bats`. Expected: PASS.
- [ ] **Step 6: Commit** `chore: chezmoi skeleton and Brewfile`.

### Task 2: Ghostty config

**Files:**
- Create: `home/dot_config/ghostty/config.ghostty`, `tests/ghostty.bats`

- [ ] **Step 1: Write the test.** Test `ghostty config validates` runs `ghostty +validate-config --config-file=home/dot_config/ghostty/config.ghostty` and asserts exit 0 with empty output. Test `ghostty effective theme` asserts `ghostty +show-config | grep '^theme = '` contains `Catppuccin Mocha`.
- [ ] **Step 2: Run the test.** Expected: FAIL (no file).
- [ ] **Step 3: Write the config** with these values:
  - Theme and font: `theme = light:Catppuccin Latte,dark:Catppuccin Mocha`, `font-family = JetBrains Mono`, `font-size = 14`.
  - Window: `window-padding-x = 10`, `window-padding-y = 8`, `window-padding-balance = true`, `macos-titlebar-style = tabs`, `background-opacity = 0.96`, `background-blur = true`.
  - Behaviour: `copy-on-select = clipboard`, `shell-integration-features = cursor,sudo,title`.
  - Command-finish alerts: `notify-on-command-finish = unfocused`, `notify-on-command-finish-after = 30s`, `notify-on-command-finish-action = bell,notify`.
  - Bell: `bell-features = system,attention,title`.
  - Quick terminal: `keybind = global:cmd+grave_accent=toggle_quick_terminal`.
  - Add a commented-out line: `# custom-shader = ` with a one-line pointer to the shader option in RUNBOOK.
- [ ] **Step 4: Apply and run the test.** Run `chezmoi apply && bats tests/ghostty.bats`. Expected: PASS. Reload Ghostty (`cmd+shift+,`) and check the colours by eye.
- [ ] **Step 5: Commit** `feat(ghostty): catppuccin, font, finish notifications, quick terminal`.

### Task 3: herdr config

**Files:**
- Create: `home/dot_config/herdr/config.toml`, `tests/herdr.bats`
- Modify: `home/.chezmoiignore` to list herdr runtime files so chezmoi never picks them up.

- [ ] **Step 1: Write the test.** Test `herdr config checks clean` runs `herdr config check` against the applied file and asserts exit 0 with no `unknown`, `ignoring`, or `invalid` in its output. Test `herdr theme values` greps the source file for `auto_switch = true` and `light_name = "catppuccin-latte"`.
- [ ] **Step 2: Run the test.** Expected: FAIL.
- [ ] **Step 3: Write the config.**
  - Top level: keep `onboarding = false`.
  - `[theme]`: use the Global Constraints values.
  - `[ui.sound]`: `enabled = true`, using the built-in sounds (no custom mp3s).
  - `[ui.toast]`: `delivery = "herdr"`.
  - Graphics: `kitty_graphics = true`, placed in whichever section herdr's built-in template lists it under. To find it, run `strings ~/.local/bin/herdr | grep -B3 kitty_graphics`; `herdr config check` must report nothing ignored.
  - Copy every other key from herdr's commented default template only if we change it (we don't).
- [ ] **Step 4: Apply, reload and test.** Run `chezmoi apply && herdr server reload-config && bats tests/herdr.bats`. Expected: PASS.
- [ ] **Step 5: Manual check.** Start an agent in a background workspace and let it finish; a sound plays. Run `herdr notification show test --sound done`; a sound and a toast appear.
- [ ] **Step 6: Commit** `feat(herdr): catppuccin auto-switch, agent sounds, toasts, kitty graphics`.

### Task 4: Claude Code speak-alert hook and settings merge

**Files:**
- Create: `home/dot_claude/hooks/executable_speak-alert.sh`, `lib/claude-hooks.fragment.json`, `lib/claude-settings-merge.sh`, `home/.chezmoiscripts/run_onchange_after_10-claude-settings.sh.tmpl`, `tests/claude-settings.bats`, `tests/speak-alert.bats`, `tests/fixtures/settings.existing.json`

**Interfaces:**
- `lib/claude-settings-merge.sh <settings-path> <fragment-path>`
  - Exit 0 after writing the merged file, or after a no-op when nothing changed.
  - Exit 2 on invalid JSON, without writing anything.
- `speak-alert.sh <stop|notify>` reads the hook JSON on stdin and uses its `cwd` field.
  - It says `"<project> finished"` for stop and `"<project> needs you"` for notify, where `<project>` is `basename "$cwd"`.
  - It runs `say -v Samantha -r 210` in the background and always exits 0.
  - Test seam: when `SPEAK_ALERT_DRY_RUN=1`, print the phrase to stdout instead of calling `say`.
- `claude-hooks.fragment.json` adds:
  - `hooks.Stop`: matcher `""`, command `~/.claude/hooks/speak-alert.sh stop`.
  - `hooks.Notification`: matcher `""`, command `~/.claude/hooks/speak-alert.sh notify`.

- [ ] **Step 1: Write `tests/claude-settings.bats`.** The fixture copies today's real structure (four SessionStart hooks, `model`, `effortLevel`, `enabledPlugins`) with dummy values only. Tests:
  - `merge adds Stop and Notification hooks`: `jq '.hooks.Stop|length'` == 1, and the command contains `speak-alert.sh stop`.
  - `merge preserves existing SessionStart hooks and unrelated keys`: SessionStart length == 4, and `.model`, `.enabledPlugins` are unchanged.
  - `merge is idempotent`: a second run gives a file `cmp`-identical to the first, with no new backup.
  - `merge creates settings when absent`: the file exists afterwards and contains only `hooks`.
  - `merge refuses invalid JSON without writing`: exit 2, and the file bytes are unchanged.
- [ ] **Step 2: Write `tests/speak-alert.bats`.** Tests:
  - `speaks project on stop`: with stdin `{"cwd":"/x/operator"}` and `SPEAK_ALERT_DRY_RUN=1`, the output is `operator finished`.
  - `speak-alert is silent when FM_TASK_ID is set`: no output, exit 0.
  - `silent when muted file exists`: uses a temporary `HOME`.
  - `exits 0 on garbage stdin`.
- [ ] **Step 3: Run both test files.** Expected: FAIL.
- [ ] **Step 4: Implement the merge and the hook script.**
  - Merge, per event key: append fragment entries whose command isn't already present; leave everything else alone.
  - Back up before the first write.
  - Write through a temporary file plus `mv`.
  - The chezmoi script embeds the fragment's and the merge script's `sha256sum` and calls the merge on `~/.claude/settings.json`.
- [ ] **Step 5: Run the tests and apply.** Run `bats tests/claude-settings.bats tests/speak-alert.bats`; expected: PASS. Then `chezmoi apply`, and confirm `jq '.hooks|keys' ~/.claude/settings.json` shows `Notification`, `SessionStart`, `Stop`.
- [ ] **Step 6: Manual check.** In a fresh Claude Code session outside the fleet, ask a one-line question. You hear "<dir> finished". Run `touch ~/.config/speak-alert/muted` and repeat: you hear nothing. Then remove the file.
- [ ] **Step 7: Commit** `feat(claude): speak-alert hook merged into settings without tracking settings.json`.

### Task 5: Rendering tools — bat, delta, glow

**Files:**
- Create: `home/dot_config/bat/config`, `home/dot_config/glow/glow.yml`, `home/.chezmoiscripts/run_onchange_after_20-gitconfig.sh`, `tests/rendering.bats`

**Interfaces:**
- The gitconfig script uses only `git config --global <key> <value>` for the keys below. It never reads or writes `user.*`.

- [ ] **Step 1: Write the test.** Tests:
  - `bat theme set`: `bat --config-file` path exists and `bat --list-themes | grep -q 'Catppuccin Mocha'`.
  - `delta is git pager`: `git config --global core.pager` == `delta`.
  - `gitconfig script is idempotent`: running it twice leaves `git config --global --list | sort` identical.
  - `user email untouched`: `git config --global user.email` is the same before and after.
- [ ] **Step 2: Run the test.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `bat/config`: `--theme-dark="Catppuccin Mocha"`, `--theme-light="Catppuccin Latte"`, `--style=numbers,changes,header`.
  - gitconfig keys:
    - `core.pager delta`, `interactive.diffFilter "delta --color-only"`
    - `delta.navigate true`, `delta.line-numbers true`, `delta.side-by-side false`, `delta.syntax-theme "Catppuccin Mocha"`
    - `merge.conflictStyle zdiff3`
  - `glow.yml`: `style: "dark"`, `width: 100`, `pager: true`.
  - If `bat --list-themes` lacks Catppuccin in the installed version, add the theme file under `home/dot_config/bat/themes/` with a `run_onchange_after_` `bat cache --build`.
- [ ] **Step 4: Apply and run the test.** Run `chezmoi apply && bats tests/rendering.bats`. Expected: PASS. By eye: `git diff` shows delta, and `glow README.md` renders.
- [ ] **Step 5: Commit** `feat(render): bat, delta, glow with catppuccin`.

### Task 6: Secret guardrails and CI

**Files:**
- Create: `.gitleaks.toml`, `.githooks/pre-commit`, `.github/workflows/ci.yml`

- [ ] **Step 1: Write the guardrails.**
  - `.githooks/pre-commit` runs `gitleaks protect --staged --redact`.
  - `git config core.hooksPath .githooks` is set for this repo only, by the runbook's bootstrap step.
  - `lib/denylist.txt` is the single list of never-tracked paths (from Global Constraints), one glob per line.
  - `.gitleaks.toml` extends the default rules and adds a path rule that rejects every glob in `lib/denylist.txt` anywhere in the tree. Keep the two in sync with a bats test: `gitleaks path rule matches denylist`.
- [ ] **Step 2: Write CI.** `ci.yml` runs on `macos-latest` with these jobs:
  - `lint`: `shellcheck` over `lib/*.sh`, `home/dot_claude/hooks/*.sh`, and `home/.chezmoiscripts/*` after `chezmoi execute-template`.
  - `test`: `bats tests/claude-settings.bats tests/speak-alert.bats`. These are the pure tests; the ghostty, herdr and render tests need a real machine and stay local.
  - `secrets`: `gitleaks detect --redact`.
- [ ] **Step 3: Verify the guardrail fires.** Stage a file `tmp/settings.json` containing `{"env":{"ANTHROPIC_API_KEY":"sk-ant-api03-FAKEFAKEFAKE"}}`. Expected: the pre-commit hook blocks the commit. Unstage and delete it.
- [ ] **Step 4: Commit** `ci: shellcheck, bats, gitleaks; pre-commit secret guard`.

### Task 7: README, RUNBOOK, publish

**Files:**
- Create: `README.md`, `RUNBOOK.md`, `CUSTOMIZE.md`

- [ ] **Step 1: Write `README.md`** (under 40 lines):
  - What the repo manages, and what it deliberately never commits.
  - A new-Mac rebuild in two commands: `brew install chezmoi` and `chezmoi init --apply --source ~/Development/dotfiles pixeloven`. The `--source` flag clones the repo straight to the path that `sourceDir` expects.
  - Day to day: `chezmoi edit`, `chezmoi diff`, `chezmoi apply`, `chezmoi re-add` for Ghostty and herdr changes made in their own editors.
- [ ] **Step 2: Write `RUNBOOK.md`.** Each runbook is a numbered checklist of at most 7 steps, ending with a "Done when" line:
  1. **New Mac bootstrap.** Install Homebrew; install herdr with its official installer into `~/.local/bin`; run `herdr integration install claude` (and `pi`); `chezmoi init --apply`; `git config core.hooksPath .githooks` in the repo. *Done when:* `bats tests/` passes.
  2. **macOS permissions.** System Settings → Notifications → Ghostty: allow alerts. *Done when:* `sleep 35` in an unfocused Ghostty tab posts a notification.
  3. **Claude Code theme.** In Claude Code run `/theme` and choose the dark theme that matches (theme choice lives in `~/.claude.json`, which we don't track). *Done when:* the status line colours match Ghostty.
  4. **Dictation.** *Option A (zero install):* System Settings → Keyboard → Dictation on, shortcut set to Fn-Fn. *Option B (better with technical terms):* install Superwhisper, pick a local English model, set a push-to-talk key, and enable "paste into active app". *Done when:* speaking into a Claude Code prompt inside herdr inserts text.
  5. **Spoken alerts on/off.** `touch ~/.config/speak-alert/muted` turns them off; `rm` turns them back on.
  6. **Optional tactical shader.** Download a scanline shader such as `crt.glsl` into `~/.config/ghostty/shaders/`, uncomment `custom-shader`, and reload. Remove it if the GPU fans spin up.
  7. **Inline images check.** Inside herdr run `brew install chafa` (if needed) and `chafa --format=kitty some.png`. If no image appears, set `kitty_graphics = false` and note it in the herdr config comment.
- [ ] **Step 3: Write `CUSTOMIZE.md`.** Give each tool one section in the same shape:
  - **Where it lives:** the repo path → the live path.
  - **Common changes:** 3–5 one-liners with the exact key and an example value.
  - **Try it:** how to reload.
  - **Keep it:** either "run `/codify`" or the exact `chezmoi edit` command.
  - **Reference:** where the tool documents every option.

  Sections and their details:

  | Section | Common changes | Reload | Reference |
  |---|---|---|---|
  | Ghostty | theme, font, padding, opacity, keybinds, shader | `cmd+shift+,` | `ghostty +show-config --default --docs`, `+list-themes`, `+list-fonts` |
  | herdr | theme or custom colours, sounds including custom mp3 paths, toasts, sidebar rows, keys | `herdr server reload-config` | the commented template in herdr's built-in config |
  | Claude Code | theme, speak-alert phrase, voice and rate, which events speak | — | the fragment-and-merge flow below |
  | bat, delta, glow | — | — | — |
  | Packages | — | — | `brew install` then `/codify`, or edit the Brewfile |

  For Claude Code, explain the merge flow: edit `lib/claude-hooks.fragment.json` and run `chezmoi apply`. Never hand-edit the hooks in `settings.json`; `/codify` reports when that has happened.

  End with a 3-line "Undo a change" section: `chezmoi diff`, `git revert`, `chezmoi apply`.
- [ ] **Step 4: Commit** `docs: README, runbooks, customization guide`.
- [ ] **Step 5: Get the operator's go-ahead to publish** (only after Task 8 is done). Stop and ask the operator to confirm creating the **public** GitHub repo `pixeloven/dotfiles`. Do not run Step 6 without it.
- [ ] **Step 6: Publish.** Run `gitleaks detect --redact` (expected: no leaks), then `gh-axi repo create pixeloven/dotfiles --public --source . --push`, and confirm the CI run is green with `gh-axi run list`.

### Task 8: Drift detection and the `/codify` skill

Run this task before Task 7's publish steps (5–6).

**Files:**
- Create: `bin/drift`, `home/dot_claude/skills/codify/SKILL.md`, `tests/drift.bats`
- Modify: `lib/claude-hooks.fragment.json` (add a SessionStart drift notice), `CUSTOMIZE.md` (link to `/codify`)

**Interfaces:**
- `bin/drift [--json]` is read-only and always exits 0. Each line is one finding in the form `<kind>\t<target>\t<suggested action>`:
  - `edited`: a managed file changed in place (from `chezmoi status`). Action: `chezmoi re-add <target>`.
  - `owned-key`: a key we own in a patched file differs from the repo. The checks are the Stop/Notification hooks in `settings.json`, the gitconfig keys from Task 5, and the speak-alert command. Action: `update lib/... then chezmoi apply`.
  - `pkg-extra`: a package installed but missing from the Brewfile (from `brew bundle cleanup --file=Brewfile`, dry run, with no `--force`). Action: `add to Brewfile`.
  - `pkg-missing`: a package in the Brewfile but not installed (from `brew bundle check`). Action: `brew bundle`.
  - `untracked-config`: a new file under `~/.config/{ghostty,herdr,bat,glow}` that chezmoi doesn't manage, excluding `lib/denylist.txt` and herdr runtime files. Action: `chezmoi add <target>`.
  - When there is no drift, print nothing.
- `bin/drift --summary` prints a single line such as `dotfiles: 3 changes not codified - run /codify`, or nothing when clean. The SessionStart hook in the fragment calls it, so every new Claude Code session tells you about drift in one line, and only when drift exists.

- [ ] **Step 1: Write `tests/drift.bats`.** Each test uses a temporary `HOME` and a temporary chezmoi source. Tests:
  - `clean state prints nothing`.
  - `in-place edit reported as edited`: apply, then append a line to the live ghostty config.
  - `hand-edited owned hook reported as owned-key`: change the Stop command in the live `settings.json`.
  - `new ghostty file reported as untracked-config`: create `~/.config/ghostty/shaders/crt.glsl`.
  - `drift never proposes a denylisted path`: create `~/.config/herdr/herdr.sock` and `~/.zshrc`, and expect neither to be reported.
  - `summary is one line or empty`.
  - Stub `brew` on `PATH` for the two package kinds; `brew` exits 1 for `check` and prints `cask "obsidian"` for `cleanup`.
- [ ] **Step 2: Run the test.** Expected: FAIL.
- [ ] **Step 3: Implement `bin/drift`** in bash, composing `chezmoi status`, `chezmoi managed`, `brew bundle check/cleanup`, `jq`, and `git config --global --get`. Filter every candidate path through `lib/denylist.txt` before printing.
- [ ] **Step 4: Run the test.** Expected: PASS. `shellcheck bin/drift` is clean.
- [ ] **Step 5: Write `SKILL.md`.**
  - Frontmatter: `name: codify`. Description: "Use when the user runs /codify, says they changed their terminal/editor config, installed a tool by hand, or a session-start line reports 'changes not codified'. Records local config changes into the dotfiles repo safely."
  - Body: the steps below, with no prose beyond them.
    1. Run `~/Development/dotfiles/bin/drift`. If it prints nothing, report "nothing to codify" and stop.
    2. Show the findings grouped by kind as a short table, with `chezmoi diff` excerpts for `edited` findings. Ask once which findings to keep, which to revert (`chezmoi apply <target>` overwrites the local change), and which to skip.
    3. For each kept finding, apply the suggested action. For `pkg-extra`, append the exact `brew`/`cask` line to the Brewfile in its section. For `owned-key`, edit the fragment or the gitconfig script, never the live file.
    4. Refuse any action whose target matches `lib/denylist.txt`. Offer instead to own just the specific key through a patch script, using `run_onchange_after_20-gitconfig.sh` as the pattern.
    5. Run `bats tests/` and `gitleaks protect --staged --redact`. If either fails, stop and report.
    6. If `CUSTOMIZE.md` doesn't already show the new kind of setting, add a one-line example for it.
    7. Commit with `chore(codify): <what changed>` and show the commit. Push only if the user says so.
- [ ] **Step 6: Add the SessionStart entry to the fragment.** It runs `~/Development/dotfiles/bin/drift --summary`. Re-run `bats tests/claude-settings.bats`; the expected Stop/Notification/SessionStart counts change by 1 (SessionStart goes from 4 to 5), so update the assertion.
- [ ] **Step 7: Manual check.**
  1. Change Ghostty's `font-size` with `ghostty +edit-config` or by direct edit, and `brew install --cask obsidian`.
  2. Open a new Claude Code session and confirm the one-line drift notice appears.
  3. Run `/codify`, keep both changes, and check that the commit contains the config and Brewfile changes.
  4. Run `bin/drift` and confirm it prints nothing.
- [ ] **Step 8: Commit** `feat: drift report and /codify skill`.
