#!/usr/bin/env bash
# CI-only Linux x86_64 binary installation. Local development uses installed tools.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/versions.env
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || { printf 'CI tools require Linux x86_64\n' >&2; exit 1; }
mode=${1:?choose checks or integration}
[[ $mode == checks || $mode == integration ]] || { printf 'unknown CI tool set: %s\n' "$mode" >&2; exit 2; }
mkdir -p .deps/tools/bin
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

download() {
  local repo=$1 tag=$2 asset=$3 checksum=$4
  gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$workspace"
  printf '%s  %s\n' "$checksum" "$workspace/$asset" | sha256sum --check
}

download neovim/neovim "v$NEOVIM_VERSION" nvim-linux-x86_64.tar.gz "$NEOVIM_LINUX_SHA256"
tar -xzf "$workspace/nvim-linux-x86_64.tar.gz" -C .deps/tools

if [[ $mode == checks ]]; then
  download JohnnyMorganz/StyLua "v$STYLUA_VERSION" stylua-linux-x86_64.zip "$STYLUA_LINUX_SHA256"
  unzip -q "$workspace/stylua-linux-x86_64.zip" -d "$workspace/stylua"
  install -m 755 "$workspace/stylua/stylua" .deps/tools/bin/stylua
  download Kampfkarren/selene "$SELENE_VERSION" "selene-$SELENE_VERSION-linux.zip" "$SELENE_LINUX_SHA256"
  unzip -q "$workspace/selene-$SELENE_VERSION-linux.zip" -d "$workspace/selene"
  install -m 755 "$workspace/selene/selene" .deps/tools/bin/selene
  download rvben/rumdl "v$RUMDL_VERSION" "rumdl-v$RUMDL_VERSION-x86_64-unknown-linux-gnu.tar.gz" "$RUMDL_LINUX_SHA256"
  mkdir "$workspace/rumdl"
  tar -xzf "$workspace/rumdl-v$RUMDL_VERSION-x86_64-unknown-linux-gnu.tar.gz" -C "$workspace/rumdl"
  install -m 755 "$workspace/rumdl/rumdl" .deps/tools/bin/rumdl
else
  download Myriad-Dreamin/tinymist "v$TINYMIST_VERSION" tinymist-x86_64-unknown-linux-gnu.tar.gz "$TINYMIST_LINUX_SHA256"
  mkdir "$workspace/tinymist"
  tar -xzf "$workspace/tinymist-x86_64-unknown-linux-gnu.tar.gz" -C "$workspace/tinymist" --strip-components=1
  install -m 755 "$workspace/tinymist/tinymist" .deps/tools/bin/tinymist
fi
printf '%s\n' "$PWD/.deps/tools/bin" "$PWD/.deps/tools/nvim-linux-x86_64/bin" >>"${GITHUB_PATH:?GITHUB_PATH is required}"
