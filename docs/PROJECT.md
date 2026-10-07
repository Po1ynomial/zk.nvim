# Project

## Goal

Provide the user-facing Neovim interface for a Typst Zettelkasten managed by `zk`.

The plugin should make creating, finding, linking, navigating, checking, and removing Zettel feel native in Neovim. It presents live server state without reimplementing archive semantics in Lua.

## Users

The primary user maintains one personal archive, works mainly in Neovim, and may open project-local archives alongside a configured fallback archive.

## Scope

- Start and attach one `zk lsp` process per local or fallback archive.
- Work alongside Tinymist for ordinary Typst language support and dictionary-member completion.
- Present live metadata search, backlinks, and open-note diagnostics.
- Create notes and check saved archive state through the CLI.
- Guard removal against modified note buffers before invoking saved-state removal.
- Route Zettel references to `zk lsp`.
- Conceal raw Zettel IDs with core target-title decorations.
- Preserve modified buffers while opening ZK-controlled targets.
- Keep closed-file and saved-template state synchronized through file notifications.

## Constraints

- Neovim 0.12 or newer
- Independent release version from `zk`
- ZK editor protocol 2 and independently validated public data schema 2
- Current development baseline of `zk` 0.3.0 with archive format 3
- A declared minimum supported engine release and pinned contract reference before plugin releases
- Rust remains authoritative for arbitrary user-declared metadata, graph state, diagnostics, and archive queries.
- Plugin behavior must remain useful without Tinymist.

See [Compatibility](COMPATIBILITY.md) for authoritative contract references and verification status.

## Non-goals

- Parsing Zettel metadata or template declarations in Lua
- Maintaining an archive graph in Lua
- Assigning semantic roles to metadata field names
- Owning a picker or completion framework
- Compiling or publishing Typst
- Installing or updating the `zk` executable
- Migrating archives or down-converting schemas
- Managing development state for the `zk` repository

## Success conditions

- Plugin startup rejects missing or unsupported protocol and data-schema versions clearly.
- Custom JSON results are version-checked before interpretation.
- Local archive discovery takes precedence over the configured fallback.
- Global archive commands work before a Zettel buffer opens.
- Navigation preserves the invocation window and modified prior buffers.
- Search, backlinks, reference completion, and decorations reflect live server state.
- Open-note diagnostics and saved archive checks are clearly distinguished.
- File and saved-template changes reach the selected server without overwriting overlays.
- Removal cannot disregard modified note buffers in the selected archive.
- Headless tests cover the declared contracts; release tests cover the minimum and latest supported engine releases once available.
