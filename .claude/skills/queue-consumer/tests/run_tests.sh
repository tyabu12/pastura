#!/bin/bash
# Self-test for the queue-consumer helper script. No Swift toolchain or
# GitHub access needed — exercises append_digest.py against fixtures,
# including the main-checkout resolver via a throwaway git repo +
# worktree (the production shape: invoked from a worktree, writes to
# the main checkout).
#
# usage: bash .claude/skills/queue-consumer/tests/run_tests.sh
set -eu
cd "$(dirname "$0")"
SCRIPTS=$(cd ../scripts && pwd)
FIXTURES=$(cd fixtures && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

SEED="# digest

<!-- queue-digest:sections -->
"

# --- explicit --digest path --------------------------------------------------
printf '%s' "$SEED" > "$TMP/digest.md"
python3 "$SCRIPTS/append_digest.py" \
  --results "$FIXTURES/results_sample.json" --digest "$TMP/digest.md" >/dev/null
grep -q "^## 2026-06-14 01:30$" "$TMP/digest.md" || fail "section heading missing"
grep -q "agent/issue-530" "$TMP/digest.md" || fail "completed row missing"
grep -q 'README \\| typo' "$TMP/digest.md" || fail "pipe not escaped in title"
grep -q "blocked-policy" "$TMP/digest.md" || fail "blocked row missing"
grep -q "queue-digest:sections" "$TMP/digest.md" || fail "marker lost"

# append-only: same run_id twice must hard-error, not duplicate
if python3 "$SCRIPTS/append_digest.py" \
  --results "$FIXTURES/results_sample.json" --digest "$TMP/digest.md" 2>/dev/null; then
  fail "duplicate run_id should be a hard error"
fi
COUNT=$(grep -c "^## 2026-06-14 01:30$" "$TMP/digest.md")
[ "$COUNT" -eq 1 ] || fail "duplicate run_id duplicated the section ($COUNT)"

# a second distinct run lands ABOVE the first (newest first)
sed 's/2026-06-14 01:30/2026-06-15 01:30/' \
  "$FIXTURES/results_sample.json" > "$TMP/results2.json"
python3 "$SCRIPTS/append_digest.py" \
  --results "$TMP/results2.json" --digest "$TMP/digest.md" >/dev/null
FIRST=$(grep -n "^## " "$TMP/digest.md" | head -1)
echo "$FIRST" | grep -q "2026-06-15" || fail "newest section not first: $FIRST"

# missing marker must hard-error, never blind-append
echo "# broken" > "$TMP/broken.md"
if python3 "$SCRIPTS/append_digest.py" \
  --results "$FIXTURES/results_sample.json" --digest "$TMP/broken.md" 2>/dev/null; then
  fail "missing marker should be a hard error"
fi

# malformed run_id / unknown outcome rejected
sed 's/2026-06-14 01:30/tonight/' \
  "$FIXTURES/results_sample.json" > "$TMP/bad_id.json"
if python3 "$SCRIPTS/append_digest.py" \
  --results "$TMP/bad_id.json" --digest "$TMP/digest.md" 2>/dev/null; then
  fail "malformed run_id should be a hard error"
fi
sed 's/blocked-policy/exploded/' \
  "$FIXTURES/results_sample.json" > "$TMP/bad_outcome.json"
if python3 "$SCRIPTS/append_digest.py" \
  --results "$TMP/bad_outcome.json" --digest "$TMP/digest.md" 2>/dev/null; then
  fail "unknown outcome should be a hard error"
fi

# --- main-checkout resolver (production shape: run from a worktree) ----------
REPO="$TMP/repo"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$REPO/data/queue"
printf '%s' "$SEED" > "$REPO/data/queue/digest.md"
git -C "$REPO" add data/queue/digest.md
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m seed
git -C "$REPO" worktree add -q "$TMP/wt" -b wt-branch

( cd "$TMP/wt" && python3 "$SCRIPTS/append_digest.py" \
    --results "$FIXTURES/results_sample.json" >/dev/null ) \
  || fail "resolver: append from worktree failed"
grep -q "^## 2026-06-14 01:30$" "$REPO/data/queue/digest.md" \
  || fail "resolver: main checkout digest not written"
grep -q "^## " "$TMP/wt/data/queue/digest.md" \
  && fail "resolver: wrote the worktree copy instead of the main checkout"

# untracked digest in the main checkout must refuse loudly
git -C "$REPO" rm -q --cached data/queue/digest.md
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m untrack
if ( cd "$TMP/wt" && python3 "$SCRIPTS/append_digest.py" \
    --results "$TMP/results2.json" >/dev/null 2>&1 ); then
  fail "resolver: untracked digest should be a hard error"
fi

echo "ALL TESTS PASSED"
