# Design

## Boundary

`zk.nvim` is an editor adapter. `zk lsp` owns parsing, metadata, links,
diagnostics, search, and live archive state. Lua owns client selection,
commands, mappings, presentation, and transient editor state.

The plugin may recognize narrow source contexts for routing and presentation.
It does not extract metadata or retain archive relations.

## Client selection

The nearest `zk.toml` above the current buffer selects a local archive. When no
local archive exists, commands use the configured session fallback.

A valid fallback starts one eager unattached client. Local archives start or
reuse separate clients as needed. Switching the fallback stops an unused prior
fallback client but preserves clients serving open local buffers.

## Protocol

During LSP initialization, the server reports:

```json
{
  "capabilities": {
    "experimental": {
      "zk": {
        "protocolVersion": 1,
        "features": {
          "archiveQueries": true,
          "categoryCompletion": true,
          "referenceCompletion": true,
          "referenceTitleDecorations": true
        }
      }
    }
  }
}
```

The plugin accepts protocol version 1 and stops clients that omit it or report
another version. Feature flags control optional behavior. Executable semantic
versions and protocol versions are independent.

## Presentation

Search uses `workspace/symbol` and `vim.ui.select`. Backlinks and diagnostics
use quickfix. ZK-controlled creation, selection, and definition navigation
replace the buffer in the invocation window while preserving modified prior
buffers as hidden.

Resolved references receive extmarks that conceal `@ID` and add the target
title as inline virtual text. Refreshes are debounced and rejected when their
buffer change tick is stale.

## Completion

`zk lsp` supplies reference and direct category completion. LSP cannot make
one server's completion response exclusive, so the plugin exports
`filter_completion_items`. Completion frontends may compose it into their own
pipeline. The plugin does not depend on or configure a completion frontend.

## Repository and releases

This repository is independent from `zk` and has its own semantic version. A
release declares its minimum engine version. Protocol additions land
compatibly in `zk` before this plugin requires them.

Full-stack tests use an explicit `ZK_BIN`. Release compatibility tests belong
in this repository. No submodule or shared SDD database connects the
repositories.
