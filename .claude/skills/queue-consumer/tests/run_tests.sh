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

# Bounded poll helpers for the flock cases below. Synchronization is by
# sentinel file / process liveness, never by a sleep margin: a cold python
# start on a loaded CI runner outruns any fixed margin, and a margin that is
# too short would fire the "did not write" assertion on a CORRECT
# implementation. Every poll is capped so a hang fails loudly, not silently.
await_file() {   # $1 = path to wait for, $2 = failure message
  i=0
  until [ -e "$1" ]; do
    i=$((i + 1)); [ "$i" -le 600 ] || fail "$2 (timed out after 60s)"
    sleep 0.1
  done
}
await_pid() {    # $1 = pid to wait to become observable, $2 = failure message
  i=0
  until kill -0 "$1" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 600 ] || fail "$2 (timed out after 60s)"
    sleep 0.1
  done
}

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

# a second distinct run lands ABOVE the first (newest first), with a
# blank line separating it from the older section's heading
sed 's/2026-06-14 01:30/2026-06-15 01:30/' \
  "$FIXTURES/results_sample.json" > "$TMP/results2.json"
python3 "$SCRIPTS/append_digest.py" \
  --results "$TMP/results2.json" --digest "$TMP/digest.md" >/dev/null
FIRST=$(grep -n "^## " "$TMP/digest.md" | head -1)
echo "$FIRST" | grep -q "2026-06-15" || fail "newest section not first: $FIRST"
OLD_LINE=$(grep -n "^## 2026-06-14 01:30$" "$TMP/digest.md" | cut -d: -f1)
PREV=$(sed -n "$((OLD_LINE - 1))p" "$TMP/digest.md")
[ -z "$PREV" ] || fail "no blank line before older section heading (got: $PREV)"

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

# local-log model: an untracked-but-present digest with the marker is
# ACCEPTED — the tracked requirement is gone (the digest is gitignored).
git -C "$REPO" rm -q --cached data/queue/digest.md
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m untrack
( cd "$TMP/wt" && python3 "$SCRIPTS/append_digest.py" \
    --results "$TMP/results2.json" >/dev/null ) \
  || fail "resolver: untracked-but-present digest should be accepted"
grep -q "^## 2026-06-15 01:30$" "$REPO/data/queue/digest.md" \
  || fail "resolver: section not written to untracked digest"

# absent digest → bootstrap a fresh scaffold (with the marker), then append
rm "$REPO/data/queue/digest.md"
sed 's/2026-06-14 01:30/2026-06-16 01:30/' \
  "$FIXTURES/results_sample.json" > "$TMP/results3.json"
( cd "$TMP/wt" && python3 "$SCRIPTS/append_digest.py" \
    --results "$TMP/results3.json" >/dev/null ) \
  || fail "resolver: absent digest should bootstrap, not error"
grep -q "queue-digest:sections" "$REPO/data/queue/digest.md" \
  || fail "resolver: bootstrap did not write the section marker"
grep -q "^## 2026-06-16 01:30$" "$REPO/data/queue/digest.md" \
  || fail "resolver: bootstrap did not append the section"

# --- the append takes an exclusive flock on <digest>.lock (#1542) -----------
# Every routine worktree resolves to the SAME main-checkout digest and this log
# is append-only, so an interleaved read-modify-write drops a whole run record
# with no key to recover it from. A helper holds the lock while an append is
# launched; the append must block, not write.
LK="$TMP/lock"; mkdir -p "$LK"
printf '%s' "$SEED" > "$LK/digest.md"
# The helper takes the flock and only THEN writes a readiness sentinel; the
# shell waits for that sentinel before launching the append, and releases the
# helper through a second sentinel once the assertion is done — so the hold
# always covers the polls without a guessed duration (the 60s inside is a
# safety cap so a broken test cannot hang CI, not a schedule).
python3 - "$LK/digest.md.lock" "$LK/held" "$LK/release" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()   # readiness sentinel: the lock is now HELD
deadline = time.time() + 60
while not os.path.exists(sys.argv[3]) and time.time() < deadline:
    time.sleep(0.05)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
HOLDER_PID=$!
await_file "$LK/held" "lock: helper never acquired the flock"
python3 "$SCRIPTS/append_digest.py" \
  --results "$FIXTURES/results_sample.json" --digest "$LK/digest.md" >/dev/null 2>&1 &
APPEND_PID=$!
await_pid "$APPEND_PID" "lock: the append process never came up"
sleep 0.5   # settle: the holder keeps the lock until the release sentinel
            # below, so a generous settle costs wall time, never a false
            # failure.
grep -q "^## 2026-06-14 01:30$" "$LK/digest.md" \
  && fail "lock: append wrote the digest while the lock was held"
: > "$LK/release"
wait "$HOLDER_PID"
wait "$APPEND_PID" || fail "lock: append failed after the lock was released"
grep -q "^## 2026-06-14 01:30$" "$LK/digest.md" \
  || fail "lock: section missing after the lock was released"

# present-but-marker-less file via the resolver → still refuses
echo "# broken, no marker" > "$REPO/data/queue/digest.md"
if ( cd "$TMP/wt" && python3 "$SCRIPTS/append_digest.py" \
    --results "$TMP/results3.json" >/dev/null 2>&1 ); then
  fail "resolver: present-but-marker-less digest should be a hard error"
fi

echo "ALL TESTS PASSED"
