# Repository boundary

Status: accepted

## Decision

`zk.nvim` is an independent repository and release. It has no Git submodule,
umbrella repository, or shared SDD state with `zk`.

Rust owns archive semantics, parsing, graph state, diagnostics, queries, and
the language-server protocol. This plugin owns Neovim workflow and
presentation. It does not parse metadata or retain a graph.

The repository was extracted from `zk` source commit `5891b57` with filtered
history for plugin-owned runtime, help, formatting, and inspection paths.
Filtered commit IDs differ, but authors, dates, messages, and relevant changes
are preserved.

## Consequences

- Releases and histories are independent.
- Cross-project features use staged protocol changes.
- Local integration selects a `zk` executable through `ZK_BIN`.
- This repository starts SDD state only when first onboarded here.
