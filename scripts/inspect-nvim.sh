#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--keep]\n' "${0##*/}"
}

keep=${KEEP_TMP:-0}
case ${1:-} in
  --keep)
    keep=1
    ;;
  "") ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for command in cargo jq nvim tinymist; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temp_root=${TMPDIR:-/tmp}
workspace=$(mktemp -d "${temp_root%/}/zk-inspect-nvim.XXXXXX")
archive="$workspace/archive"
report="$workspace/report.json"
tinymist_runtime="$workspace/tinymist-runtime"

cleanup() {
  status=$?
  if [[ $keep == 1 || $status != 0 ]]; then
    printf 'fixture workspace retained at %s\n' "$workspace" >&2
  else
    rm -rf "$workspace"
  fi
  exit "$status"
}
trap cleanup EXIT

cd "$repo_root"
printf 'building zk and creating Neovim fixture archive...\n' >&2
cargo build --quiet
zk_bin="${CARGO_TARGET_DIR:-$repo_root/target}/debug/zk"
"$zk_bin" init "$archive" >/dev/null
mkdir -p "$tinymist_runtime/lsp"
cat >"$tinymist_runtime/lsp/tinymist.lua" <<'LUA'
return {
  cmd = { assert(vim.env.ZK_TINYMIST), "lsp" },
  filetypes = { "typst" },
  root_markers = { ".git" },
}
LUA

cat >"$archive/zettel/2603231410.typ" <<'TYP'
#import "../lib/zettel.typ": zettel, abstract, keywords, category
#show: zettel

= Source note <2603231410>

#abstract[Source used by the Neovim adapter inspection.]

#keywords("source")

#category.thoughts

Link to @2603231411.
TYP

cat >"$archive/zettel/2603231411.typ" <<'TYP'
#import "../lib/zettel.typ": zettel, abstract, keywords, category
#show: zettel

= Target note <2603231411>

#abstract[Target used by the Neovim adapter inspection.]

#keywords("target")

#category.thoughts

No outgoing links.
TYP

cat >"$archive/zettel/2603231412.typ" <<'TYP'
#import "../lib/zettel.typ": zettel, abstract, keywords, category
#show: zettel

= Removable note <2603231412>

#abstract[This note has no links.]

#keywords("removable")

#category.thoughts
TYP

printf 'running headless Neovim adapter inspection...\n' >&2
ZK_REPO="$repo_root" \
ZK_ARCHIVE="$archive" \
ZK_BIN="$zk_bin" \
ZK_TINYMIST="$(command -v tinymist)" \
ZK_TINYMIST_RUNTIME="$tinymist_runtime" \
ZK_REPORT="$report" \
  nvim --clean --headless -u NONE -l "$repo_root/scripts/inspect_nvim.lua"

jq -e '
  .client == "zk"
  and .commands
  and .mappings
  and .decorations
  and .diagnostics
  and .contextDefinition
  and .backlinks
  and .search
  and .blockedRemoval
  and .successfulRemoval
  and .unsavedRemovalGuard
  and .newZettel
  and .check
  and .tinymistAttached
  and .tinymistRoot
' "$report" >/dev/null

printf 'Neovim adapter inspection result\n'
jq . "$report"
printf '\ninspection assertions passed\n' >&2
