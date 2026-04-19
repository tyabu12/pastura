#!/usr/bin/env bash
# analyze-streaming-diag.sh — parse #133 PR#4 device-run log captures.
#
# Summarises the three signals PR#5 ADR needs to pivot on:
#   (A)  parse-retry     — `retry agent=X attempt=N` + `committed … totalAttempts=N`
#   (B)  LazyVStack @State recycle — same `rowID` across ≥2 distinct `instance` UUIDs
#   (B5) cancel-race residual      — `streamTargetChange … taskNil=true|taskCancelled=true`
#
# Both A and B reproduce → PR#5 pivot (a) full C′ (trailing slot + state hoist).
# Only A reproduces      → pivot (b) retry-UX fix; skip state hoist + trailing slot.
# Neither reproduces     → pivot (c) Option 0, close #133.
#
# Usage:
#   scripts/analyze-streaming-diag.sh <session.log> [more.log ...]
#
# Accepts either a Console.app "Save As plain text" export or a
# `log stream --predicate 'subsystem == "com.pastura" AND category == "StreamingDiag"'`
# redirect. The parser matches on the message-body prefixes our Logger
# emits, so the surrounding column layout doesn't matter.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  cat >&2 <<USAGE
Usage: $0 <session.log> [more.log ...]

Each <session.log> is a plain-text capture of the com.pastura /
StreamingDiag category. See the PR description for capture steps.
USAGE
  exit 1
fi

summarise() {
  local log="$1"

  echo "======================================================"
  echo "  Session: $log"
  echo "======================================================"

  if ! [ -f "$log" ]; then
    echo "  ⚠️  File not found, skipping." >&2
    return
  fi

  local total_lines diag_lines
  total_lines=$(wc -l <"$log" | tr -d ' ')
  diag_lines=$(grep -cE \
    'retry agent=|committed agent=|onAppear rowID=|onDisappear rowID=|streamTargetChange rowID=' \
    "$log" || true)
  echo "  file lines:        $total_lines"
  echo "  diagnostic lines:  $diag_lines"
  if [ "$diag_lines" = "0" ]; then
    echo "  ⚠️  No diagnostic lines found — wrong file, or filter mismatch." >&2
    echo ""
    return
  fi
  echo ""

  # ── Hyp A: parse-retry ─────────────────────────────────────
  echo "── Hyp A — parse-retry (silent re-fire of .inferenceStarted) ──"
  local retry_count
  retry_count=$(grep -cE 'retry agent=' "$log" || true)
  echo "  retry log lines (attempt ≥ 2):  $retry_count"
  if [ "$retry_count" != "0" ]; then
    echo "  per-agent retry attempts:"
    grep -oE 'retry agent=[^ ]+ attempt=[0-9]+' "$log" |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  committed turns that required retry:"
    grep -oE 'committed agent=[^ ]+ totalAttempts=[0-9]+' "$log" |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  → Hyp A: REPRODUCED"
  else
    echo "  → Hyp A: not reproduced this session"
  fi
  echo ""

  # ── Hyp B: LazyVStack @State recycle ───────────────────────
  echo "── Hyp B — LazyVStack @State recycle ─────────────────────────"
  local recycles
  recycles=$(
    {
      grep 'onAppear rowID=' "$log" || true
    } |
      sed -E 's/.*rowID=([^ ]+).*instance=([^ ]+).*/\1 \2/' |
      sort -u |
      awk '{ print $1 }' |
      sort | uniq -c |
      awk '$1 >= 2 { print $0 }'
  )
  if [ -z "$recycles" ]; then
    echo "  0 rowIDs with ≥2 distinct instance UUIDs"
    echo "  → Hyp B: not reproduced this session"
  else
    echo "  rowIDs with ≥2 distinct instance UUIDs (count, rowID):"
    echo "$recycles" | sed 's/^/    /'
    echo ""
    echo "  → Hyp B: REPRODUCED — timelines:"
    echo "$recycles" | awk '{ print $2 }' | while read -r row; do
      echo "    ── $row ──"
      grep "rowID=$row " "$log" |
        sed -E 's/^.*\[com\.pastura:StreamingDiag\] //' |
        grep -E '^(onAppear|onDisappear|streamTargetChange)' |
        sed 's/^/      /'
    done
  fi
  echo ""

  # ── B5 residual: cancel-race ───────────────────────────────
  echo "── B5 residual — cancel-race (expected 0 after PR#147+#150) ──"
  local race_count
  race_count=$(
    {
      grep 'streamTargetChange' "$log" || true
    } | grep -cE 'taskNil=true|taskCancelled=true' || true
  )
  echo "  streamTargetChange with taskNil=true OR taskCancelled=true: $race_count"
  if [ "$race_count" != "0" ]; then
    echo "  first 5 occurrences:"
    {
      grep 'streamTargetChange' "$log" || true
    } | grep -E 'taskNil=true|taskCancelled=true' |
      head -5 |
      sed -E 's/^.*\[com\.pastura:StreamingDiag\] //' |
      sed 's/^/    /'
    echo ""
    echo "  → B5 residual detected — investigate before assuming PR#147+#150 closed it"
  else
    echo "  → B5 residual: clean"
  fi
  echo ""
}

for log in "$@"; do
  summarise "$log"
done

cat <<'VERDICT'
======================================================
  PR#5 ADR pivot matrix (fill in from above)
  ----------------------------------------------------
    A reproduced AND B reproduced → pivot (a) full C′
    only A reproduced             → pivot (b) retry-UX
    neither reproduced            → pivot (c) Option 0
======================================================
VERDICT
