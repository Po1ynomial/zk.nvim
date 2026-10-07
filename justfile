set shell := ["bash", "-euo", "pipefail", "-c"]

# Non-mutating checks; engine and Tinymist are not required.
check: format-check lint docs scripts-check test

format-check:
    stylua --check lua after tests

lint:
    selene lua after tests

docs:
    rumdl --config rumdl.toml check README.md docs

scripts-check:
    for file in scripts/*.sh scripts/versions.env; do bash -n "$file"; done

# Download the pinned, test-only mini.test dependency once.
deps:
    bash scripts/bootstrap-tests.sh

test: deps
    nvim --clean --headless -u NONE -l tests/run.lua unit

test-integration: deps
    nvim --clean --headless -u NONE -l tests/run.lua integration

test-tinymist: deps
    nvim --clean --headless -u NONE -l tests/run.lua tinymist

# Explicitly modify formatting.
fmt:
    stylua lua after tests
