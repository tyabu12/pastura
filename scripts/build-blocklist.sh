#!/usr/bin/env bash
# build-blocklist.sh — Generate or validate the runtime ContentBlocklist.json
# from docs/blocklist/source.json.
#
# Usage:
#   bash scripts/build-blocklist.sh           # generate runtime JSON
#   bash scripts/build-blocklist.sh --check   # validate; non-zero on any failure

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SOURCE="$ROOT/docs/blocklist/source.json"
DEST="$ROOT/Pastura/Pastura/Resources/ContentBlocklist.json"

VALID_CATEGORIES=("harassment" "hate" "profanity" "sexual" "violence")

JQ_FILTER='{version, patterns: [.patterns[] | {term, contentCategory}]}'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

check_shape() {
    if ! jq -e '.version == 1 and (.patterns | type) == "array"' "$SOURCE" > /dev/null 2>&1; then
        echo "ERROR: source.json failed shape check (expected .version==1 and .patterns array)" >&2
        return 1
    fi
}

check_categories() {
    local unknown
    unknown="$(jq -r '.patterns[].contentCategory' "$SOURCE" \
        | grep -v -F -x "harassment" \
        | grep -v -F -x "hate" \
        | grep -v -F -x "profanity" \
        | grep -v -F -x "sexual" \
        | grep -v -F -x "violence" \
        || true)"
    if [ -n "$unknown" ]; then
        echo "ERROR: unknown contentCategory value(s) in source.json:" >&2
        echo "$unknown" >&2
        echo "Valid values: harassment | hate | profanity | sexual | violence" >&2
        return 1
    fi
}

build_runtime_json() {
    jq "$JQ_FILTER" "$SOURCE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ "${1:-}" = "--check" ]; then
    echo "Checking source.json shape..."
    check_shape

    echo "Checking contentCategory values..."
    check_categories

    echo "Checking drift against $DEST..."
    if [ ! -f "$DEST" ]; then
        echo "ERROR: runtime file not found: $DEST" >&2
        echo "Run 'bash scripts/build-blocklist.sh' to generate it." >&2
        exit 1
    fi

    EXPECTED="$(build_runtime_json)"
    ACTUAL="$(cat "$DEST")"

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "ERROR: drift detected: source.json has been modified but ContentBlocklist.json is stale." >&2
        echo "Run 'bash scripts/build-blocklist.sh' to regenerate." >&2
        exit 1
    fi

    echo "OK: no drift detected."
else
    echo "Building $DEST from $SOURCE..."
    check_shape
    check_categories
    build_runtime_json > "$DEST"
    echo "Done: $(jq '.patterns | length' "$DEST") patterns written to $DEST"
fi
