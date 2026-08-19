#!/usr/bin/env bash
#
# scripts/tests/staged-trigger-pipefail-test.sh — regression test for #1498.
#
# THE DEFECT. Under `set -o pipefail`, `producer | grep -q PATTERN` reports the
# pipeline as FAILED when the pattern matches early: `grep -q` exits at its
# first match, the producer takes SIGPIPE and returns 141, and pipefail
# promotes that to the pipeline's status. So a *matching* input is
# indistinguishable from a non-matching one — and every consumer of the shape
# in this repo reads that status as "no match" and skips. A gate that wrongly
# RUNS gets noticed; one that wrongly SKIPS is silent.
#
# Guarded here, both by exit code:
#   - scripts/p8-precommit-gate.sh        a staged ASC / APNs key would be committed
#   - scripts/precommit-gate-classify.sh  `lint` + `build` tokens vanish, so swiftlint
#                                         and the iOS build are skipped locally, AND
#                                         ci.yml's `changes` job emits ios=false, which
#                                         skips lint-and-test / ui-test with every
#                                         required check green
#
# WHY THE SIBLING TESTS CANNOT CATCH THIS. p8-precommit-gate-test.sh and
# precommit-gate-classify-test.sh both stage a handful of paths, so the whole
# name list fits inside the pipe buffer, the producer never blocks, and the
# defect never arms. Size is the entire variable, which is why this file exists
# separately rather than as extra cases in those.
#
# READING THE ARMS. Arm A4 runs an INLINED COPY of the old shape against the
# same fixture and requires it to SKIP. That is not redundant with A1: it is
# what proves the fixture is still large enough (and the key still sorted early
# enough) to arm the defect at all. If A4 ever starts firing, A1 has gone
# vacuous — it would pass against unfixed code — and A4 fails loudly to say so.
# Do not "simplify" A4 away, and do not borrow it from a sibling suite: a
# control that lives elsewhere stops discriminating on the day the lender
# changes, without reddening anything here (#1481).
#
# Arm A8 pins that the capture SHAPE aborts on grep exit >=2 (broken regex,
# read error) instead of falling through with an empty match — it runs a
# heredoc copy, so it fixes the semantics of the idiom and is NOT a guard over
# the tree: a site relaxed back to `|| true` would still pass it. See A12's
# header for why that shape cannot be pattern-guarded. It is also the bash-5
# canary, which is A8's load-bearing job here: the fix shape was
# measured on bash 3.2 (what the macOS pre-commit hook runs); this arm is what
# reddens if bash 5 on the ubuntu CI runner treats the construct differently.
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
# Sized an ORDER OF MAGNITUDE above any pipe capacity rather than "just over"
# a constant: the capacity that arms this differs between the macOS pre-commit
# hook and the ubuntu CI runner, so a fixture tuned to one number is not
# provably armed on the other platform. A9 asserts the size that actually
# resulted, so a later edit to the generator cannot quietly shrink it.
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
# These gate every other arm. Assert them before reading any verdict, or a
# shrunken fixture turns the suite green while measuring nothing.
#
# Redirect to a file rather than piping into `wc`/`head`: `git … | head -1` is
# the defect under test, and the first draft of this file killed itself with it
# (exit 141) before reaching a single verdict. Any early-exiting reader will do
# it — reading the list once, then measuring the file, is the shape to copy.
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
# release.sh's ADR-005 §8.5 guard is `nm -a "$BIN" | xcrun swift-demangle |
# grep -i ollama`. It cannot be driven end-to-end here (it needs a signed
# archive), so the *shape* is pinned instead, on a fixture that models what
# makes the real one dangerous: an `nm` dump far larger than any pipe buffer
# with the leaked symbol near the front. Two stages upstream, not one — with
# `-q` the SIGPIPE can land on either, and only the last stage's status is the
# one `pipefail` would otherwise hide behind.
#
# The old-shape half is the negative control, same role as A4: it must MISS,
# or the fixture is not modelling the hazard and the new-shape half proves
# nothing. That the real guard was passing on symbol *ordering* rather than on
# the check is exactly this pair of results.
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

# --- A12: no `| grep -q` left in the production scripts --------------------
# Scope is the executable production surface — `scripts/*.sh`,
# `scripts/hooks/*.sh` and `tools/*/scripts/*.sh`, tracked files only.
# Deliberately NOT a pathspec over everything, because the precondition is
# "does a `pipefail` reach this site", not "where does the file live". Three
# areas were checked and are out of scope for that reason, not by omission:
#   - scripts/tests/**        this file's own A4 / A11 negative controls are
#                             literal old-shape copies and MUST stay; the other
#                             harnesses feed short strings
#   - .claude/skills/**       the run_tests.sh harnesses that carry the shape
#                             all use `set -eu` with no pipefail;
#                             release/SKILL.md's documented snippet reads a
#                             3 KB Swift file in a shell that has pipefail off
#   - .github/workflows/**    a bare `run:` is `bash -e {0}`, no pipefail
#                             (ci-workflows.md Rule 2). Latent, not live: a
#                             later `shell: bash` on one of those steps arms
#                             all four. Noted in the rule rather than guarded,
#                             because guarding it here would need this file to
#                             parse YAML step options to stay honest.
#
# Two regression shapes this arm does NOT catch, stated so the coverage is not
# read as wider than it is:
#   - `|| [ $? -eq 1 ]` relaxed back to `|| true` at a fixed site. That loses
#     the exit->=2 discrimination without reintroducing the SIGPIPE fail-open,
#     and it cannot be pattern-guarded here: legitimate `grep … || true` uses
#     already outnumber the guarded sites' worth of noise it would add. Count
#     them rather than trusting a figure — the answer moves with both the
#     enumeration below and how much of the line the pattern may span:
#       xargs grep -hE 'grep.*\|\|[[:space:]]*true' < <enumerated files>
#     A8 pins the shape's semantics; it is not a guard over the tree.
#   - a pipeline wrapped across lines (`producer |` at EOL, `grep -q …` on the
#     next). `scan` is line-bound, the same blind spot ci-workflows.md §
#     "`grep` is line-bound" documents for this repo's other call-shape guards.
#     Zero such sites today. A trailing comment on a code line goes the other
#     way and false-positives, which is loud rather than silent.
#
# Comment lines are stripped before matching. That is load-bearing and it is
# also the guard's own weak point: every site fixed for #1498 carries a comment
# that quotes the banned shape, so without stripping this arm reports its own
# documentation, and with over-eager stripping it reports nothing at all. C1-C8
# below pin both directions before the real scan is trusted.
#
# The controls are not ceremony. Two separate drafts of this pattern failed to
# compile under BWK awk (the macOS default) — first over `\{?`, then over a
# `-v`-mangled leading `|` — and on BOTH runs the scan still printed "no
# `| grep -q` remains", because a pattern that never compiles matches nothing
# and an empty result is exactly what a clean tree looks like. The controls are
# the only reason either was caught.
#
# `[^|]*` on both sides of `grep` keeps the match inside ONE pipeline stage,
# so `| { grep -E "$T" || [ $? -eq 1 ]; }` — the shape this whole PR moves to —
# does not self-report: the `-E "$T" ` between `grep` and the `||` carries no
# `q`, and `[^|]*` cannot reach past the `||` to find one. C5 pins that.
#
# The pattern is written LITERALLY in the awk program, never passed via `-v`.
# `-v` runs escape processing first, so `\|` arrives as a bare `|`, the regex
# then starts with an empty alternation, and BWK awk rejects it as an illegal
# primary — see the note above for what that failure looks like from outside.
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
# defect actually appears behind in this tree (`git`, `printf`, and a multi-stage
# pipe ending in `head`) — a pattern narrowed to one of them reads clean over
# live instances of the others, which is exactly how the original enumeration
# for this issue came up short by two sites. C7 guards the other direction: a
# stray `q` inside an unrelated argument must not be read as the `-q` flag.
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
# scripts/tests/*.sh — including THIS file and its two deliberate old-shape
# controls. Measured: 55 files without the magic, 34 with it (scripts/ only).
#
# `tools/*/scripts/*.sh` is in scope for the same reason scripts/ is, not as an
# afterthought: all four kmp-gate-spike scripts run `set -euo pipefail`, two are
# `ci.yml` gates (check-b-prime-isolation, check-suspendcontroller-drift) and a
# third runs in `kmp-nightly.yml` (stage-framework). Zero hits there today.
git -C "$ROOT" ls-files -- ':(glob)scripts/*.sh' ':(glob)scripts/hooks/*.sh' \
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
  hit="$(scan "$ROOT/$f" || true)"
  [ -z "$hit" ] || residual="${residual}${hit}
"
done < "$TMP/prod-scripts.txt"

if [ -z "$residual" ]; then
  ok "A12 no \`| grep -q\` remains in scripts/*.sh, scripts/hooks/*.sh or tools/*/scripts/*.sh"
else
  bad "A12 \`| grep -q\` under pipefail still present — each of these skips silently when" \
      "its producer outruns the pipe buffer (#1498):"
  printf '%s' "$residual" >&2
fi

if [ "$fail" -ne 0 ]; then
  echo "staged-trigger-pipefail-test: FAILED" >&2
  exit 1
fi
echo "staged-trigger-pipefail-test: all arms passed"
