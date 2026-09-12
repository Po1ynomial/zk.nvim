# zk.nvim

`zk.nvim` is the Neovim client for the `zk` Typst Zettelkasten tool. It starts
`zk lsp`, presents archive operations, and keeps archive semantics in the
server rather than duplicating them in Lua.

## Requirements

- Neovim 0.12 or newer
- A `zk` executable that implements ZK editor protocol version 1
- Tinymist when ordinary Typst language support is wanted

## Setup

Add this repository with a Neovim plugin manager, then configure an optional
personal archive:

```lua
require("zk").setup({
  archive = "~/zettelkasten",
})
```

The default commands are `{ "zk", "lsp" }` and `{ "zk" }`. Override
`lsp_cmd` or `cli_cmd` when the executable is not on `PATH`.

See `:help zk` for commands, mappings, completion, and decorations.

## Inspection

Run the headless integration suite against an explicit engine build:

```sh
ZK_BIN=/path/to/zk scripts/inspect-nvim.sh
```

The script also requires `jq`, `nvim`, and `tinymist`.
