# Design

## Boundary

`zk.nvim` is an editor adapter. `zk lsp` owns parsing, user-declared metadata, links, archive diagnostics, search, and live archive state. Lua owns client selection, commands, mappings, presentation, and transient editor state. Tinymist owns general Typst language intelligence, dictionary-member completion, rendering, and compilation.

The plugin may recognize narrow source contexts for routing and presentation. It does not extract metadata or retain archive relations. Additional metadata fields have no privileged names or implicit grouping roles.

## Client selection

The nearest `zk.toml` above the current buffer selects a local archive. An invalid nearest archive is an error, not a reason to try the configured fallback. When no local archive exists, commands use the session fallback.

A valid fallback starts one eager unattached client. Local archives start or reuse separate clients as needed. Switching the fallback stops an unused prior fallback client but preserves clients serving open local buffers. Canonical notes attach to their archive's process; library and template buffers do not become graph nodes.

Every server and CLI command receives an explicit selected `--archive` path. The server process owns that archive throughout its lifetime; `rootUri` cannot switch it. Fallback selection validates the root marker and note directory, then delegates manifest and template validation to the engine. A presentation library is not an extraction requirement.

## Compatibility

[Compatibility](COMPATIBILITY.md) records the development baseline and links the authoritative engine contracts. The plugin validates protocol 2 and data schema 2 independently before accepting a client, and validates schema-2 envelopes before using custom query results. Optional features are checked separately from standard LSP capabilities. There is no protocol-1 compatibility path.

## Source visibility and synchronization

Live search, navigation, backlinks, and decorations use the selected LSP process, including open-buffer overlays and unsaved session-only notes. Full document synchronization follows Neovim's LSP client. Dynamic watched-file registration is explicitly enabled so closed notes and saved manifest/template changes stay visible on all supported platforms. Buffer writes and successful CLI creation/removal also send file notifications.

CLI creation, checks, and removal use saved files. Unsaved template edits do not alter tracking or creation. Failed saved-schema reloads retain the engine's prior view and surface its visible error message. Removal refuses while any canonical note buffer in the selected archive is modified, because the CLI cannot guard against unsaved incoming references.

## Presentation

Search uses `workspace/symbol` and `vim.ui.select`. Symbol names are display text, not structured metadata. Backlinks and diagnostics use quickfix. ZK-controlled creation, selection, and definition navigation replace the buffer in the invocation window while preserving modified prior buffers as hidden.

`ZkDiagnostics` presents published live diagnostics for open notes. `ZkCheck` requests JSON diagnostics for saved archive state and accepts a completed integrity result with exit status 1. Both show stable diagnostic codes and supported field identifiers without matching message prose.

Resolved references receive extmarks that conceal `@ID` and add the core target title as inline virtual text. Missing targets remain distinct; unavailable titles fall back to IDs. Refreshes are debounced and rejected when their buffer change tick is stale. Custom query ranges always address UTF-8 bytes, independently of negotiated standard LSP positions.

## Completion

`zk lsp` supplies ID/title reference completion through standard LSP. Tinymist supplies dictionary-member completion. The plugin neither infers metadata roles nor depends on a completion frontend. The formerly category-specific `filter_completion_items` export remains as a deprecated pass-through for existing configurations.

## Repository and releases

This repository is independent from `zk` and has its own semantic version. A release must declare its minimum engine release and pin the corresponding contract reference. Protocol additions land compatibly in `zk` before this plugin requires them.

Engine integration tests use an explicit `ZK_BIN`; CI builds the committed development engine pinned in `scripts/versions.env`. Release compatibility tests belong in this repository. No submodule or shared workflow database connects the repositories. [Testing](TESTING.md) describes the local recipes and CI jobs.
