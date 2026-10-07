# Compatibility

## Development baseline

The plugin targets the supplied `zk` 0.3.0 development contracts:

| Interface | Supported version | Client responsibility |
| --- | --- | --- |
| ZK editor protocol | 2 | Validate initialization before attaching buffers or selecting a fallback |
| Public data schema | 2 | Validate initialization and every custom query or CLI JSON envelope |
| Archive format | 3 in the baseline engine | Let the engine validate the archive and saved template |
| Executable | 0.3.0 development baseline | Do not infer interface support from its semantic version |

There is no protocol-1 fallback, automatic archive migration, or schema downgrade. These versions are independent. The baseline is a development executable, not a claim that a tagged 0.3.0 release has been tested.

## Authoritative engine contracts

The engine owns the external interface definitions:

- [Contract status and compatibility rules](https://github.com/Po1ynomial/zk-typst/blob/a2a5f9a4b73ef6131ef071713e04229e91051554/docs/contract/README.md)
- [CLI invocation, streams, and exit statuses](https://github.com/Po1ynomial/zk-typst/blob/a2a5f9a4b73ef6131ef071713e04229e91051554/docs/contract/cli.md)
- [LSP capabilities, lifecycle, requests, and diagnostics](https://github.com/Po1ynomial/zk-typst/blob/a2a5f9a4b73ef6131ef071713e04229e91051554/docs/contract/lsp.md)
- [Shared data schema 2](https://github.com/Po1ynomial/zk-typst/blob/a2a5f9a4b73ef6131ef071713e04229e91051554/docs/contract/data.md)

These links and integration CI target the committed development baseline `a2a5f9a4b73ef6131ef071713e04229e91051554`. The engine pin lives in `scripts/versions.env`. Before a plugin release, declare the minimum supported engine release and test the corresponding release tags; a development revision is not a release compatibility matrix.

Plugin guides describe editor behavior instead of maintaining competing wire schemas.

## Client behavior

Missing optional feature flags mean false. Unknown capability properties and flags are ignored. Standard LSP capabilities determine standard-method support. Archive queries and decorations additionally require their ZK feature flags. Reference completion is disabled for clients that do not advertise the corresponding feature.

Custom archive results must have a supported envelope version before Lua uses their data. Metadata names have no built-in role. Unfamiliar metadata values are not coerced, and the plugin does not parse metadata from source. The engine provides generic hover presentation; title decorations use only core title and reference-span data. A null title falls back to the target ID.

Live quickfix diagnostics use standard Neovim diagnostic positions. Their schema-2 supplemental field identifier is displayed when available; unsupported supplemental data is left uninterpreted. Unknown diagnostic codes still follow their severity. Saved checks use structured CLI results and UTF-8 byte ranges, including completed integrity checks that exit 1. Human-facing messages are not machine-readable identifiers.

One server process owns one archive. Explicit `--archive` selects that archive before initialization; workspace parameters cannot switch it. Neovim dynamic watched-file registration is enabled for notes, the manifest, and the fixed template, including on platforms where Neovim defaults it off. Plugin writes and CLI mutations also send explicit file notifications.

CLI operations see saved files only. Open-buffer overlays belong to their LSP process. Removal is refused while any canonical note buffer in the selected archive is modified. This guard covers this Neovim instance, not unsaved state in other editors or concurrent external writers.

## Verification

`just test` runs named mini.test unit cases for both initialization versions, missing features, unknown properties, envelope rejection, unfamiliar metadata preservation, and completion-helper compatibility. It also exercises saved-check presentation with modified buffers, unknown diagnostic codes, exit status 1, unsupported schemas, incomplete JSON, and operational failures.

`just test-integration` exercises the full Neovim client against an explicit `ZK_BIN`, including generic metadata, optional-feature gating, Unicode byte ranges, live versus saved state, external file changes, saved-template reloads and failures, structured checks with exit status 1, archive selection, navigation, creation, and guarded removal. `just test-tinymist` separately checks ordinary Typst server coexistence. See [Testing](TESTING.md) for local and CI setup.

A released minimum/latest-engine compatibility matrix is not configured yet. Tests against one selected development build do not establish compatibility with other releases.
