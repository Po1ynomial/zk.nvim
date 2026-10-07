# Protocol-2 client

Status: accepted and implemented

Supersedes [ZK editor protocol](protocol.md) and [Editor behavior](editor-behavior.md). The repository boundary remains unchanged.

## Decision

Target ZK editor protocol 2 and independently advertised public data schema 2. Reject unsupported or missing initialization versions before attachment or fallback selection, and reject unsupported custom result envelopes before interpreting their data. Do not negotiate protocol 1 or down-convert schemas.

Use the `zk` 0.3.0 development contracts as the current baseline. [Compatibility](../COMPATIBILITY.md) links the authoritative CLI, LSP, and shared-data definitions and records the committed development pin. Minimum/latest release testing remains a release prerequisite. Plugin guides describe editor behavior, not duplicated wire schemas.

Metadata is a user-declared map. Lua does not parse metadata, infer semantic roles from names, evaluate Typst, or keep an archive graph. Hover presentation remains server-owned. Reference decorations use only core target titles and authored reference spans, requiring both relevant feature flags. Missing titles display the ID.

Tinymist owns dictionary-member completion. Retain the old completion-filter export temporarily as a deprecated pass-through so existing frontend configurations do not silently discard Tinymist results.

Preserve nearest-local-archive precedence, the eager session fallback, one server per archive, default mappings, and current-window navigation with modified prior buffers kept hidden. Restrict ZK attachment to canonical note paths. Pass the selected archive explicitly to each server and CLI invocation rather than treating workspace parameters as archive selection.

Enable Neovim dynamic watched-file registration, including where it is disabled by default, and explicitly notify saves and CLI file mutations. Saved manifest and template changes affect tracking; unsaved template text does not. Failed reloads retain the engine's prior view and remain visibly reported.

Distinguish published live diagnostics for open notes from saved archive checks. Checks consume structured schema-2 results, including completed integrity results with exit status 1. Show codes and supported field identifiers without matching human-facing messages. Standard positions and custom UTF-8 byte offsets remain separate.

Refuse removal while any canonical note buffer in the selected archive is modified. Only then invoke the CLI's saved-reference guard. Never discard a modified buffer if changes occur while removal is running.

## Rationale

Protocol 2 separates editor compatibility from data compatibility and replaces fixed metadata assumptions with generic typed values. Keeping source interpretation in the engine allows templates to change without Lua schema updates. Splitting live and saved operations prevents misleading archive-wide diagnostics claims and guards against deletion decisions that cannot see this editor's unsaved references.

## Consequences

- Older servers fail clearly rather than producing misinterpreted results.
- Category-specific completion integration is retired.
- Existing commands and navigation remain familiar.
- Watching is necessary for correctness but can cost more on large archive subtrees.
- Removal may require saving or discarding changes in notes other than the target.
- Protection does not cover unsaved changes in another editor or concurrent external writes.
- Release compatibility requires committed contract references and minimum/latest engine tests before a release claim.

## Verification

The mini.test unit suite tests version gates, missing feature flags, unknown properties, unfamiliar metadata, envelope rejection, pass-through completion, and structured check handling. Engine integration tests cover generic fields, optional features, Unicode ranges, live/saved visibility, file events, successful and failed template reloads, integrity checks with exit status 1, archive selection, navigation, creation, and guarded removal. Tinymist coexistence is a separate suite. See [Testing](../TESTING.md).
