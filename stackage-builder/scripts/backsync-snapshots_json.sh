#!/usr/bin/env bash

set -Eeuo pipefail

## Put snapshots.json from the new bucket into the old bucket for backward
## compatibility.

SOURCE_HTTPS_URL="https://stackage-haddock.haskell.org/snapshots.json"
TARGET_HTTPS_URL="https://s3.amazonaws.com/haddock.stackage.org/snapshots.json"
TARGET_S3_URL="s3://haddock.stackage.org/snapshots.json"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

curl --silent --fail-with-body -o "$workdir/source_snapshots.json" "$SOURCE_HTTPS_URL"
curl --silent --fail-with-body -o "$workdir/target_snapshots.json" "$TARGET_HTTPS_URL"

if ! diff "$workdir/source_snapshots.json" "$workdir/target_snapshots.json"; then
    aws s3 cp "$workdir/source_snapshots.json" "$TARGET_S3_URL"
else
    echo "No changes - not syncing snapshots.json"
fi
