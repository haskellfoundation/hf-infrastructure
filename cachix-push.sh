#!/usr/bin/env bash

set -Eeuo pipefail

## Push all flake x86_64 packages to stackage-infrastructure cache.

cache=stackage-infrastructure
flake=.

# This gathers up all packages by inspecting the json representation of the
# flake. This is a workaround for the absence of `nix build --all`. I don't
# remember where I learned to do it this way.
#
# TODO: hackage-mirror-tool requires IFD. Why?
# TODO: It's because I use callCabal2nix to build it, which requires IFD.
nix --option allow-import-from-derivation true flake show --json "$flake" \
    | jq -r  '.packages."x86_64-linux"|keys|.[]' \
    | sed 's/^/.#packages.x86_64-linux./' \
    | xargs nix build --no-link --json \
    | jq -r '.[].outputs.out ' \
    | cachix push "$cache"


profileDir=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf $profileDir" EXIT

nix develop --profile "$profileDir"/foo -c true
cachix push "$cache" "$profileDir"/foo
