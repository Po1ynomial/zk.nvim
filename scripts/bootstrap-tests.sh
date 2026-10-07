#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/versions.env
revision_file=.deps/mini.test/.revision
if [[ -f $revision_file ]]; then
  read -r installed <"$revision_file"
  if [[ $installed == "$MINI_TEST_REV" && -f .deps/mini.test/lua/mini/test.lua ]]; then
    exit 0
  fi
fi
command -v gh >/dev/null || { printf 'gh is required to bootstrap mini.test\n' >&2; exit 1; }
mkdir -p .deps
workspace=$(mktemp -d .deps/mini-test.XXXXXX)
trap 'rm -rf "$workspace"' EXIT
gh api "repos/nvim-mini/mini.test/tarball/$MINI_TEST_REV" >"$workspace/source.tar.gz"
mkdir "$workspace/plugin"
tar -xzf "$workspace/source.tar.gz" -C "$workspace/plugin" --strip-components=1
printf '%s\n' "$MINI_TEST_REV" >"$workspace/plugin/.revision"
rm -rf .deps/mini.test
mv "$workspace/plugin" .deps/mini.test
