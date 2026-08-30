#!/usr/bin/env bash
#
# scripts/tests/xcodebuild-wrapper-test.sh — regression test for #1506 / #1507.
#
# THE GAP. #1506 added a guard to scripts/xcodebuild.sh: a `for _arg in "$@"`
# loop that rejects `-scheme` / `-project` / `-derivedDataPath` / `-destination`
# reintroductions BEFORE sim-dest.sh (and its up-to-900s simulator wait) runs.
# The pre-commit hook only ever calls the wrapper with its own ACCEPTED shape
# (`build -quiet`), so a green pre-commit run — and every green CI run of the
# same hook — never exercises the rejection arms at all. Nothing else in this
# repo drives the wrapper with a REJECTED shape either. This file is that
# coverage.
#
# REAL vs STUB. This suite puts stub `xcrun` and `xcodebuild` executables at
# the FRONT of PATH so the wrapper can run its ACCEPT path — including the real
# `sim-dest.sh`, sourced unmodified — on ubuntu, with no Xcode and no simulator.
# This is the OPPOSITE choice from `simdest-errexit-test.sh`'s A5, which
# requires the REAL `xcrun` and SKIPs without it: the stub here proves the
# wrapper's own flag handling and control flow, NOT that a real
# `xcrun simctl list devices` resolves correctly against a real Simulator.app
# install. PASTURA_SIM_NAME is pinned to the stub's one device for the same
# reason: sim-dest.sh's priority list is not under test here.
# Any unexpected call reaches the stub's catch-all arm and exits 97,
# which reddens loudly rather than silently returning plausible-looking data.
#
# NEGATIVE CONTROLS ARE NOT OPTIONAL. N1-N4 (accepted shapes must still pass)
# and P3 (the P2 checker must actually flag something) are load-bearing: if
# the R-arm rejection guard swallowed everything, R1-R10 would pass for the
# wrong reason unless something here proves the wrapper still runs at all;
# if `check_invocation` stopped matching anything, P2 would pass green over a
# live regression.
#
# NOT COVERED. (1) The SPM pre-flight's own firing/skipping logic — it needs
# `$DERIVED_DATA/SourcePackages/workspace-state.json` state plus a real
# `xcodebuild -resolvePackageDependencies`; here it is only TOLERATED (every
# argv assertion below reads the LAST stub-log line, never the first, because
# the pre-flight may or may not fire depending on this worktree's DerivedData —
# see #1507 "やらないこと"). (2) The real `xcodebuild` binary's own `=`-form
# flag-drop behavior — measured by hand on Xcode 26.6 (see the guard's own
# comment in scripts/xcodebuild.sh), not pinned by any automated test, stub or
# real.
#
# CI-wired by the `*-test.sh` name (ubuntu-only "Shell gate tests" job, per
# `.claude/rules/ci-workflows.md` § "Script unit tests run in CI only"). Must
# also pass under macOS bash 3.2 (`/bin/bash`) — no `mapfile`/`readarray`, no
# `declare -A`, no `<<<`, no `${var^^}`.
#
# Run manually:
#   bash scripts/tests/xcodebuild-wrapper-test.sh
#   /bin/bash scripts/tests/xcodebuild-wrapper-test.sh

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WRAPPER="$ROOT/scripts/xcodebuild.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Snapshot BEFORE anything below runs a probe. Stub xcrun/xcodebuild never
# touch the real repo, and PASTURA_SKIP_XCSTRINGS_SYNC=1 keeps sync_xcstrings
# from creating Pastura/DerivedData/, so this should read byte-identical at
# the end — asserted there, not just assumed.
STATUS_BEFORE="$(git -C "$ROOT" status --porcelain)"

fail=0
bad() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
ok()  { printf '  ok: %s\n' "$*"; }
has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
starts_with() { case "$2" in "$1"*) return 0 ;; *) return 1 ;; esac; }

TAB="$(printf '\t')"

# Joins args with a single tab — bash-3.2-safe (no ${var^^}, no <<<). Used to
# build expected stub-log lines from an argv array without hand-typing tabs.
join_tab() {
  local IFS
  IFS="$TAB"
  printf '%s' "$*"
}

# --- Stub xcrun / xcodebuild on PATH ----------------------------------------
#
# The stub's one device. Every probe also pins PASTURA_SIM_NAME to it, so the
# accept arms do not depend on sim-dest.sh's SIMULATOR_NAMES priority list —
# which rotates with Xcode releases and would otherwise redden this file from
# an unrelated PR the day its head entry is renamed.
STUB_SIM_NAME='iPhone 17 Pro'

# xcrun: only responds to the exact `simctl list devices available --json`
# invocation sim-dest.sh's python helper makes via subprocess.check_output
# (a PATH lookup, so this stub is what actually runs). Anything else is an
# unexpected real-tool call and exits loudly rather than silently. Unquoted
# heredoc on purpose: $STUB_SIM_NAME expands now, `\$*` stays for the stub.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/xcrun" <<XCRUN_STUB
#!/bin/sh
if [ "\$*" = "simctl list devices available --json" ]; then
  printf '%s\n' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"$STUB_SIM_NAME","udid":"STUB-UDID","isAvailable":true}]}}'
  exit 0
fi
echo "stub xcrun: unexpected args: \$*" >&2
exit 97
XCRUN_STUB
chmod +x "$TMP/bin/xcrun"

# xcodebuild: appends ONE tab-joined argv line per invocation to
# $XCB_STUB_LOG, then exits with $XCB_STUB_RC (default 0) so an arm can make
# the "build" fail and watch whether the wrapper reports it. `sep` avoids a
# trailing tab so log lines compare byte-for-byte against join_tab()'s output.
cat > "$TMP/bin/xcodebuild" <<'XCB_STUB'
#!/bin/sh
{
  sep=""
  for a in "$@"; do
    printf '%s%s' "$sep" "$a"
    sep="$(printf '\t')"
  done
  printf '\n'
} >> "$XCB_STUB_LOG"
exit "${XCB_STUB_RC:-0}"
XCB_STUB
chmod +x "$TMP/bin/xcodebuild"

log="$TMP/xcb.log"
EXTRA_ENV=()
probe_out=""
probe_rc=0

# Truncates the stub log, runs the wrapper with a fully scrubbed environment
# (so an ambient *_INTEGRATION var cannot leak into an arm, and PASTURA_SIM_NAME
# is the stub's device rather than whatever the shell inherited), and captures
# combined stdout+stderr / exit status via the `printf '__RC__%s' "$?"` trick
# (mirrors simdest-errexit-test.sh's run_probe): this suite itself runs under
# `set -e`, and several arms probe a deliberate non-zero exit.
#
# PASTURA_SKIP_KMP_STAGE=1: since S5-1 (#1635) the wrapper stages the KMP
# umbrella via Gradle before xcodebuild. That is a real Kotlin/Native build
# needing a JDK and Xcode — on the ubuntu shell-tests runner it fails (exit 2)
# before the stub is ever reached, and on a developer Mac it costs a Gradle
# run per probe. The opt-out is the wrapper's own contract, and N1 asserts
# the skip arm actually fired rather than the staging call being silently
# absent.
run_wrapper() {
  : > "$log"
  probe_out="$(cd "$ROOT" && env -i PATH="$TMP/bin:$PATH" HOME="$HOME" \
      PASTURA_SKIP_SIM_WAIT=1 PASTURA_SKIP_XCSTRINGS_SYNC=1 XCB_STUB_LOG="$log" \
      PASTURA_SKIP_KMP_STAGE=1 PASTURA_SIM_NAME="$STUB_SIM_NAME" \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} /bin/bash "$WRAPPER" "$@" 2>&1; printf '__RC__%s' "$?")"
  probe_rc="${probe_out##*__RC__}"
  probe_out="${probe_out%__RC__*}"
  EXTRA_ENV=()
}

# Shared assertion for the R (rejection) arms: rc==2, the arm-specific phrase
# is present, the stub log is EMPTY (xcodebuild never reached), and "Selected
# simulator" is ABSENT (sim-dest.sh was never sourced) — pins that the
# rejection happens BEFORE anything slow, not just before the eventual
# xcodebuild call.
check_reject() {
  local name="$1" phrase="$2"
  local log_state="empty"
  [ -s "$log" ] && log_state="NONEMPTY"
  if [ "$probe_rc" = "2" ] && has "$phrase" "$probe_out" \
      && [ "$log_state" = "empty" ] && ! has "Selected simulator" "$probe_out"; then
    ok "$name"
  else
    bad "$name (rc=$probe_rc log=$log_state) output: $probe_out"
  fi
}

# Exact phrases from scripts/xcodebuild.sh's guard (copied verbatim, em-dash
# included, so a wording edit there without a matching edit here reddens).
PHRASE_R1='-destination is additive for'
# shellcheck disable=SC2016 # literal backtick, not command substitution — copied verbatim from the guard
PHRASE_R23='the `=` form is silently dropped'
# shellcheck disable=SC2016 # literal backtick, not command substitution — copied verbatim from the guard
PHRASE_R456='takes a SPACE-separated value; the `=` form is silently ignored'
PHRASE_R789='is supplied by this wrapper — drop it'

# =============================================================================
# R1-R10: rejections
# =============================================================================

run_wrapper test -destination 'platform=iOS Simulator,name=iPhone 17'
check_reject "R1 test -destination (bare, additive for test)" "$PHRASE_R1"

run_wrapper build -destination=generic/platform=iOS
check_reject "R2 build -destination=... (\`=\` form silently dropped)" "$PHRASE_R23"

run_wrapper test -destination=platform=iOS
check_reject "R3 test -destination=... (same phrase, rejected for both subcommands)" "$PHRASE_R23"

run_wrapper test -derivedDataPath=/tmp/x
check_reject "R4 test -derivedDataPath=... (\`=\` form silently ignored)" "$PHRASE_R456"

run_wrapper build -scheme=Pastura
check_reject "R5 build -scheme=... (\`=\` form silently ignored)" "$PHRASE_R456"

run_wrapper build -project=Foo.xcodeproj
check_reject "R6 build -project=... (\`=\` form silently ignored)" "$PHRASE_R456"

run_wrapper build -scheme Pastura
check_reject "R7 build -scheme (bare, wrapper-supplied)" "$PHRASE_R789"

run_wrapper test -project Foo.xcodeproj
check_reject "R8 test -project (bare, wrapper-supplied)" "$PHRASE_R789"

run_wrapper build -derivedDataPath /tmp/x
check_reject "R9 build -derivedDataPath (bare, wrapper-supplied)" "$PHRASE_R789"

run_wrapper build -quiet -derivedDataPath=/tmp/x
if [ "$probe_rc" = "2" ]; then
  ok "R10 guard fires when the rejected flag is NOT first (-quiet -derivedDataPath=...)"
else
  bad "R10 rc=$probe_rc (expected 2) when the rejected flag is not first: $probe_out"
fi

# R11-R13: the other exit-2 paths that sit before anything slow — usage, an
# unknown subcommand, and a malformed `--tail`. Not #1506's guard, but the
# same "fail fast, before sim-dest.sh" family, and one arm each to keep.
run_wrapper
if [ "$probe_rc" = "2" ] && has "Usage: scripts/xcodebuild.sh" "$probe_out"; then
  ok "R11 no arguments: usage + rc 2"
else
  bad "R11 rc=$probe_rc (expected 2 with usage) on no arguments: $probe_out"
fi

run_wrapper bogus
if [ "$probe_rc" = "2" ] && has "Unknown subcommand: bogus" "$probe_out"; then
  ok "R12 unknown subcommand: rc 2"
else
  bad "R12 rc=$probe_rc (expected 2) on unknown subcommand: $probe_out"
fi

run_wrapper build --tail x
if [ "$probe_rc" = "2" ] && has "--tail requires a positive integer" "$probe_out" \
    && ! has "Selected simulator" "$probe_out"; then
  ok "R13 --tail with a non-numeric value: rc 2 before sim-dest.sh"
else
  bad "R13 rc=$probe_rc (expected 2) on --tail x: $probe_out"
fi

# =============================================================================
# N1-N4: negative controls — accepted shapes MUST still pass. If the guard
# ever rejected everything, every R arm above would read green for the wrong
# reason without these.
# =============================================================================

# N1: the pre-commit hook's real shape.
run_wrapper build -quiet
expected_n1="$(join_tab build -scheme Pastura -project "$ROOT/Pastura/Pastura.xcodeproj" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath "$ROOT/Pastura/DerivedData" -quiet)"
last_line="$(tail -n 1 "$log")"
if [ "$probe_rc" = "0" ] && [ "$last_line" = "$expected_n1" ] \
    && has "Selected simulator: $STUB_SIM_NAME (iOS 26.0) [id=STUB-UDID]" "$probe_out" \
    && has "PASTURA_SKIP_KMP_STAGE=1: skipping KMP umbrella staging" "$probe_out"; then
  ok "N1 build -quiet (pre-commit shape): accepted, argv matches, stub-driven sim-dest.sh success path proven, KMP staging skip arm fired"
else
  bad "N1 rc=$probe_rc last_line=[$last_line] expected=[$expected_n1] output: $probe_out"
fi

# N2: --tail is consumed, not forwarded; a different exec path (`| tail -n`
# under pipefail, xtrace suppressed) must produce the SAME argv as N1.
run_wrapper build -quiet --tail 5
last_line="$(tail -n 1 "$log")"
if [ "$probe_rc" = "0" ] && [ "$last_line" = "$expected_n1" ]; then
  ok "N2 build -quiet --tail 5: --tail consumed, argv identical to N1 via the --tail exec path"
else
  bad "N2 rc=$probe_rc last_line=[$last_line] expected=[$expected_n1] output: $probe_out"
fi

# N5: the property the --tail path exists for. `.claude/rules/xcodebuild-cli.md`
# calls it pipefail-safe — a failed xcodebuild must NOT read as exit 0 through
# `| tail -n`. Drop `set -o pipefail` from the wrapper and only this arm
# reddens (N2 cannot: its stub always succeeds).
EXTRA_ENV=(XCB_STUB_RC=65)
run_wrapper build -quiet --tail 5
if [ "$probe_rc" = "65" ] && [ -s "$log" ]; then
  ok "N5 build --tail 5 with a failing xcodebuild (rc 65) exits 65 — pipefail preserved through | tail"
else
  bad "N5 rc=$probe_rc (expected 65: the stub's failure must survive the --tail pipe): $probe_out"
fi

# N3: the documented device compile-check recipe — bare -destination is
# accepted on `build` only, and BOTH the wrapper's own destination and the
# caller's must appear (TAB-bounded so "generic/platform=iOS" as a whole
# token cannot spuriously match inside "generic/platform=iOS Simulator").
run_wrapper build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
last_line="$(tail -n 1 "$log")"
if [ "$probe_rc" = "0" ] \
    && has "-destination${TAB}generic/platform=iOS Simulator${TAB}" "$last_line" \
    && has "-destination${TAB}generic/platform=iOS${TAB}CODE_SIGNING_ALLOWED=NO" "$last_line"; then
  ok "N3 build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO: both destinations present"
else
  bad "N3 rc=$probe_rc last_line=[$last_line] output: $probe_out"
fi

# N4: test's real destination comes from the stubbed sim-dest.sh (UDID-pinned).
run_wrapper test -only-testing PasturaTests/Foo
last_line="$(tail -n 1 "$log")"
if [ "$probe_rc" = "0" ] && starts_with "test${TAB}" "$last_line" \
    && has "-destination${TAB}platform=iOS Simulator,id=STUB-UDID" "$last_line" \
    && has "-parallel-testing-enabled${TAB}NO" "$last_line" \
    && has "-only-testing${TAB}PasturaTests/Foo" "$last_line"; then
  ok "N4 test -only-testing PasturaTests/Foo: stub-driven UDID destination, parallel disabled, forwarded"
else
  bad "N4 rc=$probe_rc last_line=[$last_line] output: $probe_out"
fi

# =============================================================================
# V1-V2: *_INTEGRATION advisory — the third #1506 mechanism. ADVISORY, not a
# gate: the run must still succeed either way.
# =============================================================================

EXTRA_ENV=(OLLAMA_INTEGRATION=1)
run_wrapper test -only-testing PasturaTests/Foo
log_state="empty"
[ -s "$log" ] && log_state="NONEMPTY"
if [ "$probe_rc" = "0" ] && [ "$log_state" = "NONEMPTY" ] \
    && has "warning: *_INTEGRATION set in this shell" "$probe_out" \
    && has "OLLAMA_INTEGRATION=1" "$probe_out"; then
  ok "V1 OLLAMA_INTEGRATION=1: advisory warning printed, run still succeeds and reaches xcodebuild"
else
  bad "V1 rc=$probe_rc log=$log_state output: $probe_out"
fi

# V2: no *_INTEGRATION var this time. Meaningful ONLY because run_wrapper's
# `env -i` scrubs the inherited environment: the wrapper greps ALL of `env`, so
# without that scrub a session-ambient *_INTEGRATION var would make V1 pass and
# V2 fail for the wrong reason.
run_wrapper test -only-testing PasturaTests/Foo
if [ "$probe_rc" = "0" ] && ! has "*_INTEGRATION set" "$probe_out"; then
  ok "V2 no *_INTEGRATION var set: no advisory warning printed"
else
  bad "V2 rc=$probe_rc unexpectedly printed the advisory (or failed) with no such var set: $probe_out"
fi

# =============================================================================
# Shared helpers for P1-P3
# =============================================================================

# Extracts joined invocation lines from a file: starts at a non-comment line
# matching xcodebuild.sh"? +(test|build), keeps joining while the line ends
# in a backslash (stripping it), and prints one joined line per invocation.
extract_invocations() {
  local file="$1"
  awk '
    function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
    BEGIN { in_inv = 0; buf = "" }
    {
      line = $0
      if (!in_inv) {
        t = ltrim(line)
        if (t ~ /^#/) next
        if (line !~ /xcodebuild\.sh"? +(test|build)/) next
        in_inv = 1
        buf = line
      } else {
        buf = buf " " line
      }
      tmp = buf
      sub(/[ \t]+$/, "", tmp)
      if (tmp ~ /\\$/) {
        sub(/\\$/, "", tmp)
        buf = tmp
        next
      } else {
        print buf
        in_inv = 0
        buf = ""
      }
    }
  ' "$file"
}

# Whitespace tokenization is by unquoted expansion, so pathname expansion is
# switched off around it (`set -f`): a future caller line containing `*` must
# not be retokenized against this suite's cwd. Quote-insensitive on purpose.
split_tokens() { # $1 = line; result in $tokens (array)
  set -f
  # shellcheck disable=SC2206 # unquoted on purpose: whitespace split, globbing off
  tokens=($1)
  set +f
}

# The subcommand is the token immediately after the xcodebuild.sh mention.
subcmd_of_line() {
  local line="$1" prev="" tok
  split_tokens "$line"
  for tok in ${tokens[@]+"${tokens[@]}"}; do
    if [ -n "$prev" ]; then
      case "$prev" in
        *xcodebuild.sh*)
          printf '%s' "$tok"
          return 0
          ;;
      esac
    fi
    prev="$tok"
  done
  printf ''
}

# Flags a rejected-flag-shape token. Returns 1 (flagged) on:
#   -scheme / -project / -derivedDataPath, bare or `=`-joined
#   -destination=*  (either subcommand)
#   -destination bare, only when subcmd is "test"
check_invocation() {
  local subcmd="$1" line="$2" tok
  split_tokens "$line"
  for tok in ${tokens[@]+"${tokens[@]}"}; do
    case "$tok" in
      -scheme|-scheme=*|-project|-project=*|-derivedDataPath|-derivedDataPath=*|-destination=*)
        return 1
        ;;
      -destination)
        if [ "$subcmd" = "test" ]; then
          return 1
        fi
        ;;
    esac
  done
  return 0
}

# =============================================================================
# P1: case-arm population — the guard's `case "$_arg" in` patterns match
# exactly the 8 flag shapes this file has arms for.
# =============================================================================

p1_pattern_lines="$(awk '/^for _arg in "\$@"; do/{grab=1} grab{print} grab&&/^done/{exit}' "$WRAPPER" \
  | grep -E '^[[:space:]]+-[A-Za-z=*|-]+\)$' || true)"
p1_pattern_count="$(printf '%s\n' "$p1_pattern_lines" | grep -c '.' || true)"
p1_actual="$(printf '%s\n' "$p1_pattern_lines" \
  | sed 's/)$//' \
  | tr '|' '\n' \
  | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
  | LC_ALL=C sort -u \
  | tr '\n' ' ')"
p1_actual="${p1_actual% }"
p1_expected='-derivedDataPath -derivedDataPath=* -destination -destination=* -project -project=* -scheme -scheme=*'
if [ "$p1_pattern_count" -ge 1 ] && [ "$p1_actual" = "$p1_expected" ]; then
  ok "P1 case-arm set matches exactly (a new/removed arm needs a matching arm in this test): $p1_actual"
else
  bad "P1 case-arm set mismatch — a new/removed guard arm needs a matching arm in this test." \
      "pattern_count=$p1_pattern_count actual=[$p1_actual] expected=[$p1_expected]"
fi

# =============================================================================
# P2: tracked callers — none of the wrapper's known real callers may pass a
# rejected flag shape. Discovered at runtime; fails CLOSED (zero files found
# is itself a failure, not a vacuous pass).
# =============================================================================

caller_files=()
while IFS= read -r f; do
  [ -n "$f" ] && caller_files+=("$f")
done < <(git -C "$ROOT" grep -lE 'xcodebuild\.sh"? +(test|build)' -- \
    'scripts/*.sh' 'scripts/git-hooks/*' '.github/workflows/*.yml' \
  | grep -vx 'scripts/xcodebuild.sh' \
  | grep -v '^scripts/tests/')

if [ "${#caller_files[@]}" -lt 1 ]; then
  bad "P2 discovered zero caller files — the git grep pattern or pathspecs regressed"
else
  p2_ok=1
  for f in "${caller_files[@]}"; do
    invocations=()
    while IFS= read -r inv; do
      [ -n "$inv" ] && invocations+=("$inv")
    done < <(extract_invocations "$ROOT/$f")
    if [ "${#invocations[@]}" -lt 1 ]; then
      bad "P2 $f: 0 invocation lines extracted (renamed/moved caller, or extraction regressed)"
      p2_ok=0
      continue
    fi
    for inv in "${invocations[@]}"; do
      subcmd="$(subcmd_of_line "$inv")"
      if ! check_invocation "$subcmd" "$inv"; then
        bad "P2 $f: check_invocation flagged a rejected-shape token (subcmd=$subcmd): $inv"
        p2_ok=0
      fi
    done
  done
  if [ "$p2_ok" = 1 ]; then
    ok "P2 all ${#caller_files[@]} discovered callers pass check_invocation: ${caller_files[*]}"
  fi
fi

# =============================================================================
# P3: NEGATIVE CONTROL for P2 — NOT optional. Without this, check_invocation
# could stop matching anything and P2 would stay green over a live regression.
# =============================================================================

if check_invocation "build" "build -quiet -destination=generic/platform=iOS"; then
  bad "P3a check_invocation did NOT flag 'build -quiet -destination=generic/platform=iOS' (it must)"
else
  ok "P3a check_invocation flags -destination= on build"
fi

if check_invocation "test" "test -only-testing X -destination 'platform=iOS Simulator,name=Y'"; then
  bad "P3b check_invocation did NOT flag a bare -destination on test (it must)"
else
  ok "P3b check_invocation flags bare -destination on test"
fi

if check_invocation "build" "build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO"; then
  ok "P3c check_invocation does NOT flag bare -destination on build (documented device recipe)"
else
  bad "P3c check_invocation incorrectly flagged the documented device compile-check recipe"
fi

# =============================================================================
# Final: the suite must not dirty the working tree. The target is a
# `Localizable.xcstrings` mutation by sync_xcstrings (which every arm opts out
# of) — `Pastura/DerivedData/` is gitignored and invisible here by design, so do
# not "strengthen" this with `--ignored`.
# =============================================================================

STATUS_AFTER="$(git -C "$ROOT" status --porcelain)"
if [ "$STATUS_AFTER" = "$STATUS_BEFORE" ]; then
  ok "worktree unchanged (git status --porcelain identical before/after)"
else
  bad "worktree was modified by this suite. before=[$STATUS_BEFORE] after=[$STATUS_AFTER]"
fi

if [ "$fail" -ne 0 ]; then
  printf '\nxcodebuild-wrapper-test.sh: FAILED\n' >&2
  exit 1
fi
printf '\nxcodebuild-wrapper-test.sh: all arms passed\n'
