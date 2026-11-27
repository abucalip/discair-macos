#!/usr/bin/env bash
set -euo pipefail

# Sync vendored server contract fixtures from a local navi-librarian checkout.
# Usage: scripts/sync-fixtures.sh [/path/to/navi-librarian]

SOURCE_REPO="${1:-../navi-librarian}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$SOURCE_REPO/intelligence/contract-fixtures" ]; then
    echo "error: $SOURCE_REPO/intelligence/contract-fixtures not found" >&2
    exit 1
fi

mkdir -p "$REPO_ROOT/Tests/Fixtures/contract-fixtures"
cp "$SOURCE_REPO"/intelligence/contract-fixtures/*.json "$REPO_ROOT/Tests/Fixtures/contract-fixtures/"
cp "$SOURCE_REPO/tests/fixtures/listenbrainz_inbox_responses.json" "$REPO_ROOT/Tests/Fixtures/listenbrainz_inbox_responses.json"

echo "Synced fixtures from $SOURCE_REPO into Tests/Fixtures/"
echo "Note: Tests/DiscairLibrarianTests/Fixtures and Tests/DiscairNavidromeTests/Fixtures were vendored from android/contract-fixtures/{librarian,navidrome} at the split SHA."
