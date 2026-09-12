# Project

## Goal

Provide the user-facing Neovim interface for a Typst Zettelkasten managed by
`zk`.

The plugin should make creating, finding, linking, navigating, checking, and
removing Zettel feel native in Neovim. It presents live server state without
reimplementing archive semantics in Lua.

## Users

The primary user maintains one personal archive, works mainly in Neovim, and
may open project-local archives alongside a configured fallback archive.

## Scope

- Start and attach `zk lsp` clients for local and fallback archives.
- Work alongside Tinymist for ordinary Typst language support.
- Present archive search, backlinks, diagnostics, creation, checking, and
  guarded removal.
- Route Zettel references to `zk lsp`.
- Conceal raw Zettel IDs with target-title decorations.
- Filter category completion when composed into a completion frontend.
- Preserve modified buffers while opening ZK-controlled targets.

## Constraints

- Neovim 0.12 or newer
- Independent release version from `zk`
- ZK editor protocol version 1
- A declared minimum supported `zk` release once releases begin
- Rust remains authoritative for metadata, graph state, diagnostics, and
  archive queries.
- Plugin behavior must remain useful without Tinymist.

## Non-goals

- Parsing Zettel metadata in Lua
- Maintaining an archive graph in Lua
- Owning a picker or completion framework
- Compiling or publishing Typst
- Installing or updating the `zk` executable
- Sharing SDD state with the `zk` repository

## Success conditions

- Plugin startup rejects missing or unsupported ZK protocol versions clearly.
- Local archive discovery takes precedence over the configured fallback.
- Global archive commands work before a Zettel buffer opens.
- Navigation preserves the invocation window and modified prior buffers.
- Search, backlinks, diagnostics, completion, and title decorations reflect
  live server state.
- Headless tests pass against the minimum and latest supported `zk` releases.
