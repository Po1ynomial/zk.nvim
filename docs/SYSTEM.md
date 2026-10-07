# System

## Implemented capabilities

The plugin configures a personal fallback archive with:

```lua
require("zk").setup({
  archive = "~/zettelkasten",
})
```

It starts `{ "zk", "lsp" }` by default and appends the selected `--archive` root. `lsp_cmd` and `cli_cmd` may select another executable. Initialization requires ZK protocol 2 and data schema 2; custom queries and CLI JSON checks require schema-2 envelopes. [Compatibility](COMPATIBILITY.md) records the engine development baseline and authoritative external contracts.

The plugin provides:

```text
:ZkFind [query]
:ZkBacklinks
:ZkDiagnostics
:ZkCheck
:ZkNew
:ZkRemove [ID]
:ZkRefresh
:ZkSetArchive [PATH]
```

Default buffer mappings are `gd`, `<leader>zf`, `<leader>zb`, `<leader>zd`, and `<leader>zn`. Setup can replace or disable them.

The nearest local archive wins over the session fallback. A fallback client starts eagerly, and clients for other local archives remain independent. Only canonical notes attach to ZK. Neovim handles dynamically registered file watches; the plugin enables them explicitly and supplements them with notifications for buffer writes and CLI mutations.

Search uses live workspace symbols. Backlinks and open-note diagnostics populate quickfix. Diagnostic codes and supported supplemental metadata field identifiers are shown without interpreting message prose. `ZkCheck` uses saved-state JSON diagnostics, accepts integrity results with exit status 1, and populates a separate quickfix list. Its byte ranges are converted using saved files, not modified buffers.

Creation, search selection, and ZK definition navigation use the invocation window and preserve modified buffers as hidden. Removal refuses while any canonical note buffer in the selected archive is modified, then invokes the engine's saved-reference guard.

Resolved references conceal their raw IDs and show core target titles as inline virtual text. A null title falls back to the ID. Decorations require archive-query and title-decoration flags. Reference completion follows the server's optional feature flag and standard capability. Tinymist owns dictionary-member completion; `filter_completion_items` is now a deprecated pass-through.

## Entry points

- `lua/zk/init.lua` implements setup, client lifecycle, commands, mappings, navigation, quickfix, file notifications, and decorations.
- `lua/zk/protocol.lua` validates initialization versions and custom data envelopes.
- `after/lsp/tinymist.lua` gives `zk.toml` priority as a Tinymist root marker.
- `doc/zk.txt` provides `:help zk`.
- `tests/run.lua` runs named mini.test cases in separate unit, engine, and Tinymist suites.
- `tests/helpers.lua` manages isolated child editors, fixtures, bounded waits, and cleanup.
- `justfile` defines the same development checks and test recipes used in CI.
- `.github/workflows/ci.yml` runs checks and pinned-engine integration on Ubuntu.

## Verification

```sh
just check
ZK_BIN=/path/to/zk just test-integration
ZK_BIN=/path/to/zk just test-tinymist
```

`just check` runs StyLua, Selene, rumdl, shell syntax checks, and unit tests without an engine or Tinymist. Markdown checks explicitly use `rumdl.toml`, which disables MD013. Integration tests create temporary archives with template-declared generic metadata and verify client selection, navigation, diagnostics, search, decorations, Unicode ranges, live/saved source visibility, watched files, successful and failed saved-schema reloads, creation, checking, and guarded removal.

The separate Tinymist suite verifies shared root discovery and reference handling using a diagnostic control label. Failure fixtures and LSP logs remain under `.test-results/`; successful fixtures and child processes are cleaned up. [Testing](TESTING.md) describes dependencies, tool pins, filtering, CI, and deferred LuaLS checks.

## Current limitations

Search uses `vim.ui.select` without preview. Backlinks and diagnostics use quickfix. The plugin requests target metadata once per distinct outgoing target during each decoration refresh and has no cross-buffer title cache. Separate archive queries are not a transaction.

LSP diagnostics cover open notes only. CLI operations cannot see unsaved state in another editor. Removal protection covers modified canonical note buffers in this Neovim instance, not concurrent external writers.

Native watching is explicitly enabled even where Neovim defaults it off; large unrelated archive subtrees may increase watcher cost. Saved-file events are asynchronous, so an immediately following query is not guaranteed to have processed a disk change yet.

CI tests the committed development engine pinned in `scripts/versions.env`. Compatibility testing against released minimum and latest engine versions is not configured yet. LuaLS type checking and additional operating-system or Neovim matrices are deferred.
