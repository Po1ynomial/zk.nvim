# System

## Implemented capabilities

The plugin configures a personal fallback archive with:

```lua
require("zk").setup({
  archive = "~/zettelkasten",
})
```

It starts `{ "zk", "lsp" }` by default and validates ZK editor protocol
version 1 before accepting a client. `lsp_cmd` and `cli_cmd` may select another
executable.

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

Default buffer mappings are `gd`, `<leader>zf`, `<leader>zb`, `<leader>zd`,
and `<leader>zn`. Setup can replace or disable them.

The nearest local archive wins over the session fallback. A fallback client
starts eagerly, and clients for other local archives remain independent.

Search uses live workspace symbols. Backlinks and diagnostics populate
quickfix. Creation, search selection, and ZK definition navigation use the
invocation window and preserve modified buffers as hidden.

Resolved references conceal their raw IDs and show target titles as inline
virtual text. Direct category completion can exclude results from other
servers through the exported `filter_completion_items` helper.

## Entry points

- `lua/zk/init.lua` implements setup, client lifecycle, commands, mappings,
  navigation, quickfix, completion filtering, and decorations.
- `lua/zk/protocol.lua` validates the ZK editor protocol descriptor.
- `after/lsp/tinymist.lua` gives `zk.toml` priority as a Tinymist root marker.
- `doc/zk.txt` provides `:help zk`.
- `scripts/inspect-nvim.sh` runs the headless full-stack inspection.

## Inspection

```sh
stylua --check lua scripts after
ZK_BIN=/path/to/zk scripts/inspect-nvim.sh
rumdl check README.md docs
```

The integration script requires `jq`, Neovim 0.12, and Tinymist. It creates
temporary archives and verifies protocol validation, client selection,
navigation, diagnostics, search, completion filtering, decorations, checking,
creation, and guarded removal.

## Current limitations

Search uses `vim.ui.select` without preview. Backlinks and diagnostics use
quickfix. The plugin requests target metadata once per distinct outgoing
target during each decoration refresh and has no cross-buffer title cache.

Compatibility testing against released minimum and latest engine versions is
not configured yet.
