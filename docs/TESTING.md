# Testing

## Local commands

Install Neovim 0.12 or newer, just, StyLua, Selene, and rumdl. Run commands from the repository root:

```sh
just check
```

This checks Lua formatting, Lua lint, Markdown, shell syntax, and unit tests without changing source files. `just fmt` deliberately rewrites Lua formatting.

The first test run downloads the pinned mini.test dependency into the ignored `.deps/` directory using `gh`. This is a development dependency only. A plugin manager, the user's Neovim configuration, `zk`, and Tinymist are not needed for unit tests. Subsequent runs reuse the pinned dependency and do not need network access.

Run individual suites with:

```sh
just test
ZK_BIN=/absolute/path/to/zk just test-integration
ZK_BIN=/absolute/path/to/zk just test-tinymist
```

The engine executable must be selected explicitly. Tinymist tests also require `tinymist` on `PATH`, or an explicit `TINYMIST_BIN`. Missing dependencies fail the selected suite rather than silently skipping tests. To filter named cases:

```sh
TEST_FILTER='saved checks' just test
TEST_FILTER='external create' ZK_BIN=/absolute/path/to/zk just test-integration
```

A filter that collects no cases fails. Do not set `TEST_FILTER` for a full verification run.

## Suite boundaries

| Suite | Dependencies | Coverage |
| --- | --- | --- |
| Unit | Neovim and mini.test | Version gates, envelopes, completion-helper compatibility, command registration, structured checks, errors, and removal guards |
| Engine integration | Unit dependencies and an explicit `zk` build | Archive selection, clients, generic metadata, navigation, quickfix, decorations, creation/removal, live versus saved state, file watching, and schema reloads |
| Tinymist integration | Engine dependencies and Tinymist | Server coexistence, archive-root selection, and reference handling with a diagnostic control label |

Tests use mini.test's native named sets. Stateful cases run in fresh child Neovim processes with `tests/minimal_init.lua`. `tests/helpers.lua` creates temporary archives and supplies bounded waits and process cleanup. Helpers and fixtures are shared; test success is reported directly by mini.test, not through a generated success report.

Asynchronous assertions have deadlines, and CLI processes have a timeout. Teardown stops language servers, force-stops any that outlive the grace period, then stops the child editor. Successful fixture directories are deleted. Failed cases retain their archives and LSP logs under `.test-results/`, and the reporter prints the location. The directory is ignored by Git.

## Tool configuration

- `.stylua.toml` defines formatting for runtime and test Lua.
- `selene.toml` uses Lua 5.1 plus the local `vim.yml` definition. Neovim's dynamic `vim` table is allowed, not arbitrary global variables. Mixed tables are permitted for LSP positions and configuration.
- `rumdl.toml` explicitly disables MD013. `just docs` passes this file to rumdl, so line-width policy does not depend on a developer's global config.
- `scripts/versions.env` is the source of CI tool versions, release archive checksums, the mini.test revision, and the engine revision.

CI currently uses Neovim 0.12.5, just 1.58.0, StyLua 2.5.2, Selene 0.32.0, rumdl 0.2.78, and Tinymist 0.15.8. Local tools may differ, but a version-dependent failure must be checked against these pins. When updating pins, update checksums and any corresponding contract links together.

## Continuous integration

`.github/workflows/ci.yml` runs on pull requests, pushes to `main`, and manual dispatch. It has two independent jobs on Ubuntu 24.04:

- `Checks` installs the pinned tools and runs `just check`.
- `Integration` checks out the public engine at the pinned revision, builds it with its Rust toolchain and locked dependencies, then runs the engine and Tinymist recipes.

GitHub Actions are pinned to commit SHAs. Downloaded CI editor/linter/server archives are verified against repository-pinned SHA-256 checksums. Permissions are read-only, checkout credentials are not persisted, jobs have timeouts, and superseded runs are cancelled. Rust cache writes are limited to `main`. Failure artifacts contain only the test fixture directories and logs, retained for seven days.

These jobs fail on test failures and missing dependencies. Repository branch protection must select their check names to make them merge requirements; adding a workflow alone does not configure branch protection.

## Deferred checks

LuaLS static type checking is deferred until the runtime's configuration, protocol values, and callback boundaries have useful annotations and a portable Neovim type-library configuration. There is no advisory job that is expected to fail indefinitely.

The initial workflow tests one pinned Neovim and one pinned development engine. A released minimum/latest-engine matrix, nightly Neovim, additional operating systems, coverage thresholds, and screenshots are not part of this suite.
