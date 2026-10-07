# zk.nvim

`zk.nvim` is the Neovim client for the `zk` Typst Zettelkasten engine. It starts one `zk lsp` process per archive and presents note search, references, backlinks, diagnostics, creation, and guarded removal. Archive semantics stay in the engine rather than being duplicated in Lua.

## Requirements

- Neovim 0.12 or newer
- A `zk` executable implementing ZK editor protocol 2 and public data schema 2
- Tinymist when ordinary Typst language support and dictionary-member completion are wanted

The current development baseline is `zk` 0.3.0 with archive format 3. Older protocols are not supported. See [Compatibility](docs/COMPATIBILITY.md) for the authoritative engine contracts and release status.

## Setup

Add this repository with a Neovim plugin manager, then configure an optional personal archive:

```lua
require("zk").setup({
  archive = "~/zettelkasten",
})
```

The nearest local `zk.toml` takes precedence over the personal fallback. The default commands are `{ "zk", "lsp" }` and `{ "zk" }`. Override `lsp_cmd` or `cli_cmd` when the executable is not on `PATH`. The plugin appends `--archive` with the selected root to both commands.

Live search and navigation include unsaved notes. `ZkCheck` inspects saved archive state and puts structured diagnostics in quickfix. Removal refuses while any canonical note buffer in the selected archive has unsaved changes, then uses the engine's saved-reference guard.

See `:help zk` for commands, mappings, completion, and decorations.

## Development

Run formatting, lint, documentation, and unit tests with:

```sh
just check
```

Run engine integration and the separate Tinymist suite against an explicit build:

```sh
ZK_BIN=/path/to/zk just test-integration
ZK_BIN=/path/to/zk just test-tinymist
```

See [Testing](docs/TESTING.md) for dependencies, test selection, tool pins, and CI. Markdown checks explicitly disable MD013 through the repository's `rumdl.toml`.
