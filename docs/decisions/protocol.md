# ZK editor protocol

Status: superseded by [Protocol-2 client](protocol-2-client.md). The protocol-1 decision below is retained as history.

## Decision

The plugin and engine have independent semantic versions. Each plugin release
declares a minimum supported engine release.

`zk lsp` reports an integer protocol version and feature flags in
`capabilities.experimental.zk`. This plugin accepts protocol version 1 and
rejects missing or unsupported versions before attaching buffers or selecting
a fallback.

Feature flags describe optional behavior. The plugin checks them rather than
inferring support from the executable version. Version 1 currently advertises
archive queries, category completion, reference completion, and reference
title decorations.

## Testing

This repository owns Neovim end-to-end compatibility tests. Once releases
exist, CI runs against the minimum and latest supported `zk` releases. A
scheduled non-gating job may test `zk` main.

## Lineage

The initial protocol contract was implemented in `zk` source commit `5891b57`
and extracted into this repository as filtered commit `5ec586a`.
