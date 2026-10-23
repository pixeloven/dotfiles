#!/bin/sh
# Set the git keys we own; ~/.gitconfig itself is never tracked (it holds name/email).
# Only the keys below are written. user.* is never read or written.
set -eu
git config --global core.pager delta
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.line-numbers true
git config --global delta.side-by-side false
git config --global delta.syntax-theme "Catppuccin Mocha"
git config --global merge.conflictStyle zdiff3
