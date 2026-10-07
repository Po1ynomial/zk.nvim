# Editor behavior

Status: superseded by [Protocol-2 client](protocol-2-client.md). The earlier category-completion ownership below is retained as history; archive selection and current-window navigation remain in the replacement.

## Decision

The plugin selects the nearest archive above the current buffer before its
configured session fallback. A valid fallback starts eagerly so global archive
commands work from unrelated buffers.

ZK-controlled creation, search selection, and definition navigation display
the target in the invocation window. A modified prior buffer remains hidden
with its changes intact. Asynchronous results fall back to the current window
only when the invocation window has closed.

Reference completion supports numeric ID prefixes and case-insensitive title
queries. Direct category completion comes from `zk lsp`; the plugin provides a
frontend-neutral filter because LSP cannot make one server exclusive.

Resolved references conceal the authored ID and display the target title.
Missing targets remain visibly distinct.

## Rationale

Archive discovery should follow the current editing context before personal
configuration. Current-window navigation avoids surprising splits while
preserving unsaved work. Archive semantics and completion candidates remain in
the server, while Lua controls their Neovim presentation.

## Lineage

This decision factors the accepted Neovim behavior previously recorded in
`zk` under `docs/decisions/lsp.md` and
`docs/decisions/global-archive-access.md` through source commit `5891b57`.
