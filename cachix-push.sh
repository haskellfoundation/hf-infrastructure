#!/usr/bin/env bash

set -Eeuo pipefail

## Push all flake x86_64 packages to stackage-infrastructure cache.

cache=stackage-infrastructure
flake=.

# TODO: hackage-mirror-tool requires IFD. Why?
nix --option allow-import-from-derivation true flake show --json "$flake" \
    | jq -r  '.packages."x86_64-linux"|keys|.[]' \
    | sed 's/^/.#packages.x86_64-linux./' \
    | xargs nix build --no-link --json \
    | jq -r '.[].outputs.out ' \
    | cachix push "$cache"
