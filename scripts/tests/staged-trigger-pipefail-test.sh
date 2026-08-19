#!/usr/bin/env bash
#
# scripts/tests/staged-trigger-pipefail-test.sh — regression test for #1498.
#
# THE DEFECT. Under `set -o pipefail`, `producer | grep -q PATTERN` reports the
# pipeline as FAILED when the pattern matches early — so a *matching* input is
# indistinguishable from a non-matching one, and every consumer of the shape in
# this repo reads that as "no match" and skips. Mechanism and the alternatives
# that do NOT fix it: `.claude/rules/ci-workflows.md` § "Rule 3".
#
# Guarded here by exit code: scripts/p8-precommit-gate.sh (a staged ASC / APNs
# key would be committed) and scripts/precommit-gate-classify.sh (`lint` +
# `build` vanish, so swiftlint and the iOS build are skipped locally AND
# ci.yml's `changes` job emits ios=false, skipping lint-and-test / ui-test with
# every required check green).
#
# WHY THE SIBLING TESTS CANNOT CATCH THIS. p8-precommit-gate-test.sh and
# precommit-gate-classify-test.sh stage a handful of paths, which fits inside
# the pipe buffer, so the producer never blocks and the defect never arms. Size
# is the entire variable — hence a separate file rather than cases in those.
#
# READING THE ARMS. A4 and A11 run INLINED COPIES of the old shape and require
# it to MISS: that is what proves each fixture still arms the defect at all. If
# either starts catching, its paired arm has gone vacuous — it would pass
# against unfixed code. Do not "simplify" them away, and do not borrow a control
# from a sibling suite: it stops discriminating on the day the lender changes,
# without reddening anything here (#1481).
#
# A8 pins that the capture SHAPE aborts on grep exit >=2 rather than reading
# empty. It runs a heredoc copy, so it fixes the idiom's semantics and is NOT a
# guard over the tree (a site relaxed to `|| true` still passes it — see A12 for
# why that cannot be pattern-guarded). It doubles as the bash-5 canary: the fix
# was measured on bash 3.2, what the macOS pre-commit hook runs.
#
# CI-wired: the `*-test.sh` naming convention makes this a gate under
# .github/workflows/ci.yml ("Run scripts/tests/*-test.sh"). Run manually:
#   bash scripts/tests/staged-trigger-pipefail-test.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P8_GATE="$ROOT/scripts/p8-precommit-gate.sh"
CLASSIFY="$ROOT/scripts/precommit-gate-classify.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
bad() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
ok()  { printf '  ok: %s\n' "$*"; }

# --- fixture ---------------------------------------------------------------
# Sized an ORDER OF MAGNITUDE above any pipe capacity rather than "just over" a
# constant: that capacity differs between the macOS pre-commit hook and the
# ubuntu CI runner. A9 asserts the size that actually resulted, so a later edit
# to the generator cannot quietly shrink it.
PAD="$(awk 'BEGIN{ for (i = 0; i < 190; i++) printf "x" }')"

# Tail paths start `zz/` so they sort AFTER the `keys/` and `Pastura/` heads
# below. `git diff --cached --name-only` emits in sorted order, so the head is
# what `grep -q` matches — it exits on line 1 with ~all of the list unwritten,
# which is the condition that arms the defect. A10 asserts that ordering.
awk -v pad="$PAD" 'BEGIN{ for (i = 0; i < 3000; i++) printf "zz/%s_%05d.txt\n", pad, i }' \
  > "$TMP/tail.txt"

P8_PATH='keys/AuthKey_TEST123.p8'
SWIFT_PATH='Pastura/Pastura/Engine/Fixture.swift'

{ echo "$P8_PATH"; cat "$TMP/tail.txt"; }    > "$TMP/list-p8-big.txt"
{ cat "$TMP/tail.txt"; }                      > "$TMP/list-clean-big.txt"
{ echo "$P8_PATH"; }                          > "$TMP/list-p8-small.txt"
{ echo "$SWIFT_PATH"; cat "$TMP/tail.txt"; } > "$TMP/list-swift-big.txt"
{ echo "$SWIFT_PATH"; }                       > "$TMP/list-swift-small.txt"
# All-SAFE: `docs/` is on the classifier's build-irrelevant denylist, so the
# correct answer is the empty token set. Distinguishes "correctly quiet" from
# "silently disarmed", which look identical in the classifier's output.
awk -v pad="$PAD" 'BEGIN{ for (i = 0; i < 3000; i++) printf "docs/%s_%05d.md\n", pad, i }' \
  > "$TMP/list-safe-big.txt"

# Stage a path list into a throwaway repo via `update-index --index-info`
# against one empty blob — no working-tree files, so the fixture costs a single
# git call instead of thousands of creat()s.
make_repo() { # $1 = repo dir, $2 = path list
  git init -q "$1"
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  blob="$(printf '' | git -C "$1" hash-object -w --stdin)"
  awk -v b="$blob" '{ printf "100644 %s\t%s\n", b, $0 }' "$2" > "$TMP/index-info"
  git -C "$1" update-index --index-info < "$TMP/index-info"
}

make_repo "$TMP/p8-big"    "$TMP/list-p8-big.txt"
make_repo "$TMP/p8-clean"  "$TMP/list-clean-big.txt"
make_repo "$TMP/p8-small"  "$TMP/list-p8-small.txt"

# --- A9 / A10: the fixture's own preconditions ------------------------------
# These gate every other arm: a shrunken fixture would turn the suite green
# while measuring nothing. Redirect to a file rather than piping into
# `wc`/`head` — `git … | head -1` is the defect under test, and the first draft
# of this file killed itself with it (exit 141) before any verdict.
git -C "$TMP/p8-big" diff --cached --name-only > "$TMP/staged-p8-big.txt"

size="$(wc -c < "$TMP/staged-p8-big.txt" | tr -d ' ')"
if [ "$size" -gt 262144 ]; then
  ok "A9 staged name list is $size bytes (> 256 KiB)"
else
  bad "A9 staged name list is only $size bytes — too small to arm the defect;" \
      "every other arm below is now vacuous"
fi

first="$(head -1 "$TMP/staged-p8-big.txt")"
if [ "$first" = "$P8_PATH" ]; then
  ok "A10 the .p8 sorts first, so grep -q would exit on line 1"
else
  bad "A10 first staged path is '$first', expected '$P8_PATH' — the key no longer" \
      "sorts early, so the producer finishes before grep exits and A1 goes vacuous"
fi

# --- A4: negative control — the OLD shape must still fail open --------------
cat > "$TMP/old-shape.sh" <<'OLD_SHAPE'
set -euo pipefail
if git diff --cached --name-only | grep -qE '\.p8$'; then
  exit 1
fi
exit 0
OLD_SHAPE
set +e
( cd "$TMP/p8-big" && bash "$TMP/old-shape.sh" ) >/dev/null 2>&1
old_rc=$?
set -e
if [ "$old_rc" -eq 0 ]; then
  ok "A4 the old shape skips on this fixture (defect is armed — A1 is meaningful)"
else
  bad "A4 the old shape caught the .p8 (rc=$old_rc) — the fixture no longer arms the" \
      "defect, so A1 would pass against unfixed code. Fix the fixture, not this arm."
fi

# --- A1 / A2 / A3: the real p8 secret gate ---------------------------------
set +e
( cd "$TMP/p8-big" && bash "$P8_GATE" ) >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  ok "A1 p8 gate rejects a staged key behind a huge staged list"
else
  bad "A1 p8 gate ACCEPTED a staged .p8 behind a huge staged list — an App Store" \
      "Connect / APNs private key would be committed (#1498)"
fi

set +e
( cd "$TMP/p8-clean" && bash "$P8_GATE" ) >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  ok "A2 p8 gate passes a huge staged list with no key"
else
  bad "A2 p8 gate rejected a huge staged list containing no .p8 (rc=$rc)"
fi

set +e
( cd "$TMP/p8-small" && bash "$P8_GATE" ) >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  ok "A3 p8 gate rejects a staged key on a small list (positive control)"
else
  bad "A3 p8 gate accepted a staged .p8 on a SMALL list (rc=$rc) — the gate is broken" \
      "outright, independently of #1498"
fi

# --- A5 / A6 / A7: the changeset classifier --------------------------------
# `build` is the load-bearing token: ci.yml's `changes` job maps its absence to
# ios=false, skipping lint-and-test and ui-test with all required checks green.
out="$(bash "$CLASSIFY" < "$TMP/list-swift-big.txt")"
if [ "$out" = "lint build" ]; then
  ok "A5 classifier emits 'lint build' for a huge Swift-bearing changeset"
else
  bad "A5 classifier emitted '$out' (expected 'lint build') for a huge Swift-bearing" \
      "changeset — swiftlint and the iOS build are skipped locally and ios=false on CI"
fi

out="$(bash "$CLASSIFY" < "$TMP/list-swift-small.txt")"
if [ "$out" = "lint build" ]; then
  ok "A6 classifier emits 'lint build' for a small Swift changeset (positive control)"
else
  bad "A6 classifier emitted '$out' (expected 'lint build') on a SMALL changeset — the" \
      "classifier is broken outright, independently of #1498"
fi

out="$(bash "$CLASSIFY" < "$TMP/list-safe-big.txt")"
if [ -z "$out" ]; then
  ok "A7 classifier stays quiet for a huge all-docs changeset (negative control)"
else
  bad "A7 classifier emitted '$out' for an all-docs changeset (expected empty)"
fi

# --- A8: the capture shape must abort on grep exit >= 2 ---------------------
cat > "$TMP/rc-shape.sh" <<'RC_SHAPE'
set -euo pipefail
STAGED="$(cat "$1")"
MATCHED="$(printf '%s\n' "$STAGED" | { grep -E "$2" || [ $? -eq 1 ]; })"
printf 'reached-end:%s\n' "${MATCHED:+matched}"
RC_SHAPE
set +e
bash "$TMP/rc-shape.sh" "$TMP/list-p8-big.txt" '\.p8\' >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  ok "A8 capture shape aborts on a broken pattern (grep rc>=2) instead of reading empty"
else
  bad "A8 capture shape swallowed a broken pattern and continued — grep rc>=2 is being" \
      "read as 'no match', which is the same fail-open #1498 fixes. On the ubuntu runner" \
      "this also means bash 5 does not abort the assignment the way bash 3.2 does."
fi

# --- A11: the three-stage symbol-guard shape (scripts/release.sh) ----------
# release.sh's ADR-005 §8.5 guard needs a signed archive, so the *shape* is
# pinned instead on a fixture modelling what makes the real one dangerous: an
# `nm` dump far past any pipe buffer with the leaked symbol near the front. Two
# stages upstream, not one — with `-q` the SIGPIPE can land on either, and only
# the last stage's status is the one `pipefail` would otherwise hide behind.
# The old-shape half is the negative control (see A4 in the header).
awk 'BEGIN {
  print "0000000100000000 T _$s7Pastura13OllamaServiceCN"
  for (i = 0; i < 40000; i++) printf "00000001000%05d T _symbol_filler_%d\n", i, i
}' > "$TMP/nm-dump.txt"

cat > "$TMP/symbol-guard.sh" <<'SYMBOL_GUARD'
set -euo pipefail
if [ "$2" = "old" ]; then
  if cat "$1" | cat | grep -iq ollama; then echo CAUGHT; else echo MISSED; fi
else
  LEAKED="$(cat "$1" | cat | { grep -i ollama || [ $? -eq 1 ]; })"
  if [ -n "$LEAKED" ]; then echo CAUGHT; else echo MISSED; fi
fi
SYMBOL_GUARD

old_v="$(bash "$TMP/symbol-guard.sh" "$TMP/nm-dump.txt" old)"
new_v="$(bash "$TMP/symbol-guard.sh" "$TMP/nm-dump.txt" new)"
if [ "$old_v" = "MISSED" ] && [ "$new_v" = "CAUGHT" ]; then
  ok "A11 symbol-guard shape: old MISSED / new CAUGHT on a $(wc -c < "$TMP/nm-dump.txt" | tr -d ' ')-byte dump"
elif [ "$old_v" = "CAUGHT" ]; then
  bad "A11 the old shape caught the leak — the fixture no longer models the hazard," \
      "so the new-shape half is vacuous. Fix the fixture, not this arm."
else
  bad "A11 capture shape MISSED an ollama symbol in a large nm dump — scripts/release.sh" \
      "would ship a leaking archive (ADR-005 §8.5)"
fi

# --- A13: a non-ASCII staged path must not walk past an anchored TRIGGER ----
# A second fail-open of the same family, at the same lines: with the default
# `core.quotepath`, git octal-escapes a non-ASCII path AND double-quotes it, so
# the leading `"` defeats a `^`-anchored prefix and the trailing `"` a
# `$`-anchored extension. Driven through the p8 gate because its verdict is an
# exit code, and a key is the worst thing to let through. The ASCII arm is the
# positive control: without it a non-ASCII pass says nothing about quoting.
for variant in "keys/AuthKey_日本語.p8:non-ASCII" "keys/AuthKey_ASCII.p8:ASCII control"; do
  path="${variant%%:*}"; label="${variant#*:}"
  repo="$TMP/nonascii-$(printf '%s' "$label" | tr -cd 'A-Za-z')"
  printf '%s\n' "$path" > "$TMP/one-path.txt"
  make_repo "$repo" "$TMP/one-path.txt"
  set +e
  ( cd "$repo" && bash "$P8_GATE" ) >/dev/null 2>&1
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    ok "A13 p8 gate rejects a staged key named in $label"
  else
    bad "A13 p8 gate ACCEPTED a staged .p8 named in $label — git quotes and" \
        "octal-escapes such a path, so the trailing quote defeats the \`\\.p8\$\`" \
        "anchor. The producer needs \`-c core.quotepath=false\` (#1498)."
  fi
done

# --- A12: no `| grep -q` left in the production scripts --------------------
# THIS ARM GUARDS ONE SHAPE, NOT THE CLASS. It scans for `grep -q` behind a
# pipe; ANY early-exiting reader (`head`, `sed …q`, `awk …exit`, `grep -m N`)
# has the same defect. `scripts/analyze-streaming-diag.sh` was a live `head`
# instance inside this very pathspec that this scan could not see, fixed on the
# same branch. Extending `scan` to those readers would need its own C-controls
# and would fire on many correct `| head` uses, so the split is deliberate:
# mechanical guard for the shape, `.claude/rules/ci-workflows.md` § "Rule 3"
# for the class.
#
# Scope is the executable production surface — `scripts/*.sh`,
# `scripts/hooks/*.sh`, `scripts/git-hooks/*` and `tools/*/scripts/*.sh`,
# tracked files only. The predicate is "does a `pipefail` reach this site", not
# "where does the file live", which is why four areas are out of scope by
# argument rather than by omission — none of them by an input-size claim, which
# § Rule 3 forbids:
#   - scripts/tests/**      not shipped gates, so a false pass here fails the
#                           tests it guards rather than production. A4 / A11
#                           are literal old-shape copies and MUST stay.
#   - .claude/skills/**     every site is outside a `pipefail` scope (`set -eu`
#                           harnesses; release/SKILL.md's snippet is ad hoc).
#   - .github/workflows/**  a bare `run:` is `bash -e {0}`, no pipefail — latent,
#                           not live. Guarding it would mean parsing YAML step
#                           options; it is covered inline and in § Rule 3.
#   - docs/**               two documented snippets: ADR-028's cannot exit early
#                           at all (its `tr '\n' ' '` leaves the stream with no
#                           line to match), and release-checklist.md's runs
#                           interactively, without pipefail.
#
# Two regression shapes this arm does NOT catch, stated so the coverage is not
# read as wider than it is:
#   - `|| [ $? -eq 1 ]` relaxed back to `|| true`. That loses the exit->=2
#     discrimination without reintroducing the SIGPIPE fail-open, and cannot be
#     pattern-guarded: `grep … || true` is a legitimate idiom in these same
#     scripts, so the guard would be noise. A8 pins the shape's semantics
#     instead. Count rather than trust a figure — the answer moves with how much
#     of the line the pattern may span:
#       xargs grep -hE 'grep[^|]*\|\|[[:space:]]*true' < "$TMP/prod-scripts.txt" | wc -l
#   - a pipeline wrapped across lines (`producer |` at EOL, `grep -q …` next).
#     `scan` is line-bound, the blind spot ci-workflows.md § "`grep` is
#     line-bound" documents for this repo's other call-shape guards. Zero such
#     sites today. A trailing comment on a code line false-positives instead,
#     which is loud rather than silent.
#
# Comment lines are stripped before matching — load-bearing, and the guard's own
# weak point: every site fixed for #1498 carries a comment quoting the banned
# shape, so without stripping this arm reports its own documentation, and with
# over-eager stripping it reports nothing. C1-C8 pin both directions.
#
# The controls are not ceremony. Two drafts of this pattern failed to compile
# under BWK awk (the macOS default) and BOTH still printed "no `| grep -q`
# remains": a pattern that never compiles matches nothing, and an empty result
# is exactly what a clean tree looks like.
#
# `[^|]*` on both sides of `grep` keeps the match inside ONE pipeline stage, so
# the fixed shape `| { grep -E "$T" || [ $? -eq 1 ]; }` does not self-report —
# `[^|]*` cannot reach past the `||` to find a `q`. C5 pins that.
#
# The pattern is written LITERALLY in the awk program, never passed via `-v`:
# `-v` runs escape processing first, so `\|` arrives bare, the regex starts with
# an empty alternation, and BWK awk rejects it as an illegal primary.
scan() { # $@ = files; echoes offending "file:line: text"
  awk '
    { probe = $0; sub(/^[[:space:]]+/, "", probe) }
    substr(probe, 1, 1) == "#" { next }
    probe ~ /\|[^|]*grep[[:space:]][^|]*(-[A-Za-z]*q|--quiet)/ {
      print FILENAME ":" FNR ": " $0
    }
  ' "$@"
}

# C1-C8: a CLASS control, not a self-match. C1/C2/C6 are the three producers the
# defect appears behind in this tree (`git`, `printf`, a multi-stage pipe ending
# in `head`) — a pattern narrowed to one reads clean over live instances of the
# others, which is how the original enumeration came up two sites short. C7
# guards the other direction: a stray `q` in an unrelated argument is not `-q`.
cat > "$TMP/control.sh" <<'CONTROL'
if ! git diff --cached --name-only | grep -qE "$T"; then exit 0; fi
  if printf '%s\n' "$X" | grep -q foo; then echo hi; fi
# Capture, don't `| grep -q`: this comment must NOT be reported.
   # indented comment quoting `| grep -qE "$T"` must NOT be reported either.
MATCHED="$(printf '%s\n' "$S" | { grep -E "$T" || [ $? -eq 1 ]; })"
if git show "HEAD:$p" 2>/dev/null | head -n 14 | grep -q '^paths:'; then :; fi
cat x | sed -e 's/seq//' | grep -E 'foo'
LEAKED="$(nm -a "$B" | xcrun swift-demangle | { grep -i ollama || [ $? -eq 1 ]; })"
CONTROL
ctl="$(scan "$TMP/control.sh" || true)"
must_hit=""
must_miss=""
for n in 1 2 6; do
  case "$ctl" in *":$n: "*) : ;; *) must_hit="${must_hit}C$n " ;; esac
done
for n in 3 4 5 7 8; do
  case "$ctl" in *":$n: "*) must_miss="${must_miss}C$n " ;; esac
done
if [ -z "$must_hit" ] && [ -z "$must_miss" ]; then
  ok "A12 control: catches git-fed / printf-fed / head-fed old shapes; ignores comments," \
     "both fixed shapes, and an unrelated 'seq' argument"
else
  bad "A12 control failed — missed: [${must_hit:-none}] false-positive: [${must_miss:-none}]." \
      "The scan below cannot be trusted: a pattern that stops compiling or stops matching" \
      "reports zero hits, which is indistinguishable from a clean tree. Reported lines:" "$ctl"
fi

# `:(glob)` is required, not decoration: a plain `scripts/*.sh` pathspec uses
# git's wildmatch, where `*` crosses `/`, so it silently pulls in
# scripts/tests/*.sh — including THIS file and its deliberate old-shape controls.
#
# `tools/*/scripts/*.sh` qualifies for the same reason scripts/ does: those
# scripts run `set -euo pipefail` and three are CI gates. `scripts/git-hooks/*`
# needs its own entry because those files are EXTENSIONLESS — `pre-commit` is
# not `*.sh`, so no `scripts/*` glob reaches it.
git -C "$ROOT" ls-files -- ':(glob)scripts/*.sh' ':(glob)scripts/hooks/*.sh' \
                           ':(glob)scripts/git-hooks/*' \
                           ':(glob)tools/*/scripts/*.sh' \
  > "$TMP/prod-scripts.txt"
n_files="$(wc -l < "$TMP/prod-scripts.txt" | tr -d ' ')"
if [ "$n_files" -lt 30 ]; then
  bad "A12 only $n_files production scripts enumerated — the ls-files pathspec stopped" \
      "matching, so a clean scan would prove nothing"
else
  ok "A12 scanning $n_files tracked production scripts"
fi

residual=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # No `|| true` on the scan: an awk that cannot read the file would otherwise
  # return empty, which is byte-identical to "this file is clean". The whole
  # point of C1-C8 is that a silent zero is the failure mode here.
  set +e
  hit="$(scan "$ROOT/$f")"
  scan_rc=$?
  set -e
  if [ "$scan_rc" -ne 0 ]; then
    bad "A12 scan failed on $f (awk rc=$scan_rc) — a failed scan reads as a clean" \
        "file, so treat this as unscanned rather than passing"
  fi
  [ -z "$hit" ] || residual="${residual}${hit}
"
done < "$TMP/prod-scripts.txt"

if [ -z "$residual" ]; then
  ok "A12 no \`| grep -q\` remains in any of the $n_files enumerated production scripts"
else
  bad "A12 \`| grep -q\` under pipefail still present — each of these skips silently when" \
      "its producer outruns the pipe buffer. There is no exemption: rewrite it to capture," \
      "per .claude/rules/ci-workflows.md § \"Rule 3\", which also explains why an" \
      "intermediate variable alone does NOT fix it. If the producer genuinely must not be" \
      "drained, \`; [ \"\${PIPESTATUS[1]}\" -eq 0 ]\` is correct too — but teach it to \`scan\`" \
      "and give it a C-control before using it, or this arm will keep calling it a defect" \
      "(#1498). Offending lines:"
  printf '%s' "$residual" >&2
fi

if [ "$fail" -ne 0 ]; then
  echo "staged-trigger-pipefail-test: FAILED" >&2
  exit 1
fi
echo "staged-trigger-pipefail-test: all arms passed"
