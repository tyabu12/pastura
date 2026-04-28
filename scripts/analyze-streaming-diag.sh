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
# `log stream --predicate 'subsystem == "com.tyabu12.Pastura" AND category == "StreamingDiag"'`
# redirect. The parser matches on the message-body prefixes our Logger
# emits, so the surrounding column layout doesn't matter.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  cat >&2 <<USAGE
Usage: $0 <session.log> [more.log ...]

Each <session.log> is a plain-text capture of the com.tyabu12.Pastura /
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
  # Pattern list extended in #194 PR#a Item 4 for `repaired` (A2 success)
  # and `retryCause` (cause-tagged retry) lines emitted by LLMCaller. The
  # field-order in those lines is load-bearing — see LLMCaller.swift.
  diag_lines=$(grep -cE \
    'retry agent=|committed agent=|streamReset agent=|onAppear rowID=|onDisappear rowID=|streamTargetChange rowID=|repaired agent=|retryCause agent=' \
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

  # ── Hyp A': silent stream re-issue (suspend-resume path) ───
  echo "── Hyp A' — silent stream re-issue (suspend-resume bypasses .inferenceStarted) ──"
  local reset_count diverge_count shrink_count
  reset_count=$(grep -cE 'streamReset agent=' "$log" || true)
  diverge_count=$(grep -cE 'streamReset .*type=diverge' "$log" || true)
  shrink_count=$(grep -cE 'streamReset .*type=shrink' "$log" || true)
  echo "  streamReset total:               $reset_count"
  echo "    type=shrink  (new is strict prefix of existing): $shrink_count"
  echo "    type=diverge (new not prefix-related):           $diverge_count"
  if [ "$reset_count" != "0" ]; then
    echo ""
    echo "  per-agent reset counts:"
    grep -oE 'streamReset agent=[^ ]+' "$log" |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  first 5 occurrences:"
    grep -E 'streamReset agent=' "$log" |
      head -5 |
      sed -E 's/^.*\[com\.tyabu12\.Pastura:StreamingDiag\] //' |
      sed 's/^/    /'
    echo ""
    echo "  → Hyp A': REPRODUCED — LLMCaller's consumeStreamWithSuspendRetry"
    echo "     re-issued the stream without firing .inferenceStarted."
    echo "     shrink = deterministic re-issue (same tokens regenerated);"
    echo "     diverge = non-deterministic re-issue (different content)."
  else
    echo "  → Hyp A': not reproduced this session"
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
        sed -E 's/^.*\[com\.tyabu12\.Pastura:StreamingDiag\] //' |
        grep -E '^(onAppear|onDisappear|streamTargetChange)' |
        sed 's/^/      /'
    done
  fi
  echo ""

  # ── B5 residual: cancel-race ───────────────────────────────
  # Split streamTargetChange events into 4 buckets:
  #   (a) no_op:       visibleChars >= newTarget (target shrunk or fully revealed; reveal loop idle)
  #   (b) continuing:  visibleChars < newTarget AND task running (ideal post-PR#147)
  #   (c) restart_nil: visibleChars < newTarget AND taskNil=true (task finished between tokens; normal)
  #   (d) restart_cancelled: visibleChars < newTarget AND taskCancelled=true (B5 residual — should be 0)
  #
  # (d) is the only bucket that directly indicates the cancel-race PR#147+#150 targeted.
  # High (c) is expected when cps > stream rate (task catches up and exits between tokens).
  # Flicker is subjective — watch the device; the script only bounds the race surface.
  echo "── B5 residual — cancel-race surface (see script comment for buckets) ──"
  awk '
    /streamTargetChange/ {
      vc = 0; nt = 0; tn = "false"; tc = "false"
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^visibleChars=/)   { split($i, a, "="); vc = a[2] + 0 }
        if ($i ~ /^newTarget=/)      { split($i, a, "="); nt = a[2] + 0 }
        if ($i ~ /^taskNil=/)        { split($i, a, "="); tn = a[2] }
        if ($i ~ /^taskCancelled=/)  { split($i, a, "="); tc = a[2] }
      }
      total++
      if (vc >= nt)            { noop++ }
      else if (tc == "true")   { rcancelled++ }
      else if (tn == "true")   { rnil++ }
      else                     { cont++ }
    }
    END {
      printf "  total streamTargetChange events: %d\n", total+0
      printf "    (a) no-op (visibleChars >= newTarget):           %d\n", noop+0
      printf "    (b) continuing (task still revealing; ideal):    %d\n", cont+0
      printf "    (c) restart from nil (normal post-PR#147):       %d\n", rnil+0
      printf "    (d) restart from cancelled (B5 residual signal): %d\n", rcancelled+0
    }
  ' "$log"
  local rcancelled_count
  rcancelled_count=$(
    awk '
      /streamTargetChange/ && /taskCancelled=true/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^visibleChars=/) { split($i, a, "="); vc = a[2] + 0 }
          if ($i ~ /^newTarget=/)    { split($i, a, "="); nt = a[2] + 0 }
        }
        if (vc < nt) c++
      }
      END { print c+0 }
    ' "$log"
  )
  if [ "$rcancelled_count" != "0" ]; then
    echo ""
    echo "  ⚠️  (d) is non-zero — investigate. First 5 occurrences:"
    awk '
      /streamTargetChange/ && /taskCancelled=true/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^visibleChars=/) { split($i, a, "="); vc = a[2] + 0 }
          if ($i ~ /^newTarget=/)    { split($i, a, "="); nt = a[2] + 0 }
        }
        if (vc < nt) print
      }
    ' "$log" | head -5 |
      sed -E 's/^.*\[com\.tyabu12\.Pastura:StreamingDiag\] //' |
      sed 's/^/    /'
    echo "  → B5 residual: REPRODUCED (cancel-race surface still exercised)"
  else
    echo "  → B5 residual: clean (cancel-race surface not triggered this session)"
  fi
  echo ""
  echo "  Note: flicker is a subjective visual signal. Low (d) == cancel-race race"
  echo "        surface wasn't exercised, but doesn't prove absence of flicker from"
  echo "        other causes. Watch the device during the session."
  echo ""

  # ── #194 PR#a — A2 repair successes ────────────────────────
  # Per-kind buckets: unclosed_string / unclosed_brace / composite ("+"-joined).
  # The trailing-comma repair was dropped (Apple's JSONSerialization accepts
  # `{"a":1,}` natively on iOS 17+); see JSONResponseParser.swift.
  echo "── A2 repair successes (JSONResponseParser leniency, #194) ──"
  local repaired_count
  repaired_count=$(grep -cE 'repaired agent=' "$log" || true)
  echo "  repaired log lines:  $repaired_count"
  if [ "$repaired_count" != "0" ]; then
    echo "  per-kind counts:"
    grep -oE 'repaired .*kind=[a-z_+]+' "$log" |
      grep -oE 'kind=[a-z_+]+' |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  per-agent repair counts:"
    grep -oE 'repaired agent=[^ ]+' "$log" |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  → A2 repair pipeline FIRED — these would have been retries pre-#194."
  else
    echo "  → No A2 repairs this session (parse succeeded as-is, or repair guard rejected)."
  fi
  echo ""

  # ── #194 PR#a — Retry cause breakdown ──────────────────────
  # `retryCause` lines tag WHY a retry was triggered (parse_failed vs
  # empty_field). Helps disambiguate post-#194 measurement: if Hyp A
  # frequency drops, did A2 repair help (parse_failed↓ + repaired↑) or
  # did A3 prompt hardening help (empty_field↓)?
  echo "── Retry cause breakdown (LLMCaller retry decisions, #194) ──"
  local rc_count
  rc_count=$(grep -cE 'retryCause agent=' "$log" || true)
  echo "  retryCause log lines:  $rc_count"
  if [ "$rc_count" != "0" ]; then
    echo "  per-cause counts:"
    grep -oE 'retryCause .*cause=[a-z_]+' "$log" |
      grep -oE 'cause=[a-z_]+' |
      sort | uniq -c | sort -rn | sed 's/^/    /'
    echo ""
    echo "  per-agent retry causes:"
    grep -oE 'retryCause agent=[^ ]+ attempt=[0-9]+ cause=[a-z_]+' "$log" |
      sort | uniq -c | sort -rn | sed 's/^/    /'
  else
    echo "  → No retries decided this session."
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
    A reproduced AND B reproduced  → pivot (a) full C′
    only A reproduced              → pivot (b) retry-UX
    neither reproduced             → pivot (c) Option 0

  Note: Hyp A' (silent stream re-issue) is orthogonal to the above.
  If A' reproduces but A / B don't, the fix lives in BG suspend/resume
  UX (related to #84 / #135), not in the #133 display-redesign axes.
======================================================
VERDICT
