#!/usr/bin/env bash
#
# scripts/release.sh — Pastura TestFlight release driver (ADR-014).
#
# The deterministic half of the release. fastlane (fastlane/Fastfile) is
# the uploader only; this script owns everything else in ADR-014's
# "Release flow (ordered)":
#
#   preflight  → assert HEAD == origin/<default> AND every required CI
#                check (derived from the branch ruleset) is green on it
#   version    → read intent from --version; build = git rev-list --count
#   guard      → assert the build number strictly exceeds the latest
#                TestFlight build for this version (via fastlane)
#   archive    → xcodebuild archive (Release), build number injected as a
#                CURRENT_PROJECT_VERSION override (no pbxproj edit)
#   symbol     → re-run the ADR-005 §8.5 Ollama-symbol guard on the
#                ARCHIVED binary (CI only checks the unsigned build product)
#   kn-dsym    → WARN if the Kotlin/Native PasturaSharedEngine dSYM is absent
#                from the archive (ADR-023 §6 S5-3, H7 symbolication)
#   export     → xcodebuild -exportArchive, method app-store-connect, with an
#                exportOptions.plist generated at cut time (never committed)
#   kn-symbols → WARN if the exported .ipa carries no Symbols/<UUID>.symbols
#                for the K/N dSYM UUIDs (ASC would not symbolicate K/N frames)
#   upload     → fastlane upload_to_testflight
#   tag        → annotated tag v<version>+<build>, pushed ONLY after the
#                upload succeeds (a failed upload leaves no dangling tag)
#   preserve   → copy the xcarchive into ~/Library/Developer/Xcode/Archives so
#                Organizer can symbolicate the H7 TestFlight crash locally
#
# Bootstrap prerequisites (one-time, human; ADR-014 § bootstrap): an ASC
# app record, an API key, and a signed-in Xcode Apple ID whose account can
# sign for distribution. Modern Xcode uses cloud-managed distribution
# signing — the cert's private key is NOT in the local keychain — so the
# archive/export below pass -allowProvisioningUpdates (see their why-notes).
# The key's identifiers are read from the environment:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH  (see fastlane/Fastfile)
#
# Usage:
#   scripts/release.sh --version X.Y[.Z] [--notes-file PATH] [--dry-run]
#   scripts/release.sh --self-test
#
#   --notes-file PATH  Use PATH's contents as the TestFlight "What to Test"
#               changelog — the channel by which the /release skill ships its
#               reviewed, tester-facing notes. Omitted: the changelog falls
#               back to commit subjects since the last tag (build_notes). A
#               given-but-missing or empty file is a hard error, never a
#               silent fall back to raw subjects.
#   --dry-run   Run preflight + build-number computation and print the
#               planned release (including the notes preview, so a bad
#               --notes-file fails here), then stop BEFORE the ASC query,
#               archive, and upload (those require the bootstrap above).
#               Safe to run on any CI-green main checkout.
#   --self-test Exercise the ADR-023 §6 S5-3 symbolication helpers against
#               throwaway fixtures under $WORK, then exit. Needs no gh, no
#               network and no signing — it never reaches preflight, ASC, or a
#               real archive. Run it after editing those helpers.
#
# macOS bash 3.2 safe (no mapfile / declare -A / here-strings) so the same
# script is reusable from a GHA macos-* runner later (ADR-014 Decision 2).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

readonly PROJECT="Pastura/Pastura.xcodeproj"
readonly SCHEME="Pastura"
readonly APP_NAME="Pastura"
readonly TEAM_ID="52G26234A3"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── ADR-023 §6 S5-3 (H5/H7) symbolication helpers ───────────────────────
# The first TestFlight build carrying the Kotlin/Native umbrella also carries
# an intentional Kotlin crash (H7, ADR-004 §9.2), so its K/N frames must
# symbolicate BOTH on App Store Connect and locally in Organizer. The three
# helpers below cover that.
#
# ALL THREE ARE WARNING-ONLY THIS CYCLE. They assert Xcode behaviour nobody has
# observed on this project yet — whether the K/N dSYM lands in the xcarchive at
# all, and whether `-exportArchive` writes a matching `.symbols` into the .ipa.
# A wrong assumption baked into a `die` would block a release over a check that
# is itself unverified, which is strictly worse than shipping and reading the
# warning. FOLLOW-UP: promote the two checks to `die` in a separate PR once the
# S5-3 release cycle has observed the real paths (#1673, ADR-023 §6 S5-3).

# Locate the Kotlin/Native dSYM inside an xcarchive and print its UUID(s) on
# stdout, one per line (progress/diagnostics go to stderr, so the caller can
# capture the UUIDs with a plain command substitution). Never fails the script.
check_kn_dsym_in_archive() {
  local archive="$1"
  local dwarf="$archive/dSYMs/PasturaSharedEngine.framework.dSYM/Contents/Resources/DWARF/PasturaSharedEngine"
  if [ ! -f "$dwarf" ]; then
    err "warning: Kotlin/Native dSYM not found at $dwarf — H7 Kotlin frames may not symbolicate anywhere. (warning-only this cycle; see the FOLLOW-UP note above)"
    return 0
  fi
  # `dwarfdump --uuid` prints one `UUID: <uuid> (<arch>) <path>` line per slice;
  # field 2 is the UUID token. Capture-then-test, never `| grep -q`: an
  # early-exiting reader under pipefail turns a match into a pipeline failure
  # (.claude/rules/ci-workflows.md § "Rule 3").
  # `|| true`: the producer's OWN exit status is the other hazard. A file that
  # exists but is not a readable Mach-O makes dwarfdump exit non-zero, pipefail
  # promotes it, and `set -e` would abort the release after a finished archive
  # — the exact outcome the warning-only design forbids. The empty-UUID branch
  # below is the intended landing.
  local uuids
  uuids="$(dwarfdump --uuid "$dwarf" 2>/dev/null | awk '/^UUID:/ { print $2 }' || true)"
  if [ -z "$uuids" ]; then
    err "warning: dwarfdump reported no UUID for $dwarf — cannot verify the ASC symbol upload."
    return 0
  fi
  log "  ✓ K/N dSYM present; UUID(s): $(printf '%s' "$uuids" | tr '\n' ' ')" >&2
  printf '%s\n' "$uuids"
}

# Assert the exported .ipa carries a Symbols/<UUID>.symbols entry for every K/N
# dSYM UUID — that payload is what App Store Connect symbolicates crash reports
# from. Never fails the script.
check_kn_symbols_in_ipa() {
  local ipa="$1"
  shift
  if [ "$#" -eq 0 ]; then
    err "warning: ASC symbol check skipped — no Kotlin/Native dSYM UUID was found in the archive."
    return 0
  fi
  local listing="$WORK/ipa-listing.txt"
  if ! unzip -l "$ipa" > "$listing" 2>/dev/null; then
    err "warning: could not list $ipa — ASC symbol check skipped."
    return 0
  fi
  local u norm missing=0 count="$#"
  for u in "$@"; do
    # Xcode names each file Symbols/<UUID>.symbols with uppercase hex + dashes.
    # Normalise the UUID and match case-insensitively, so neither side's casing
    # can turn a present payload into a spurious warning. grep reads a FILE
    # here, so there is no upstream producer for -q to SIGPIPE (Rule 3).
    norm="$(printf '%s' "$u" | tr '[:lower:]' '[:upper:]')"
    if grep -Fiq "Symbols/$norm.symbols" "$listing"; then
      # stdout is free here — unlike check_kn_dsym_in_archive, nothing
      # captures this helper's output, so `log` needs no >&2.
      log "  ✓ Symbols/$norm.symbols present in the .ipa"
    else
      err "warning: no Symbols/$norm.symbols in $(basename "$ipa") — Kotlin/Native frames for UUID $norm will NOT symbolicate on App Store Connect / TestFlight. Organizer will still symbolicate them from the preserved local archive copy."
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -eq 0 ] || err "  ($missing of $count K/N UUID(s) missing from the ASC symbol payload; warning-only this cycle)"
  return 0
}

# Copy the xcarchive into the Organizer archive library.
# Why: $WORK — and the archive inside it — is destroyed by the EXIT trap, so
# without this copy Organizer has no local dSYMs to match the H7 TestFlight
# crash against. It runs AFTER the tag push, where a `die` would recreate the
# dangling-tag state this script exists to prevent, so it must never abort.
preserve_archive() {
  local archive="$1" version="$2" build="$3"
  local dest_dir dest
  dest_dir="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
  dest="$dest_dir/$APP_NAME $version+$build.xcarchive"
  # A same-day re-cut at the same version+build would make `cp -R` nest the
  # archive INSIDE the existing destination (unindexable by Organizer) while
  # still reporting success, so an existing destination gets a time suffix.
  [ ! -e "$dest" ] || dest="${dest%.xcarchive}-$(date +%H%M%S).xcarchive"
  if mkdir -p "$dest_dir" && cp -R "$archive" "$dest"; then
    log "Archive preserved at $dest (Organizer indexes it for H7 symbolication)"
  else
    err "warning: archive copy failed — H7 symbolication will need the dSYMs re-downloaded from ASC"
  fi
  return 0
}

# ── --self-test ─────────────────────────────────────────────────────────
# Drives the three helpers above against throwaway fixtures. No gh, no network,
# no signing — so it is runnable on any checkout, unlike the rest of this file.
self_test() {
  local fail=0 total=0 out root uuid up dwarf_dir fake_home ro_home stamp
  bad() { printf 'FAIL: %s\n' "$*" >&2; fail=1; total=$((total + 1)); }
  ok()  { printf '  ok: %s\n' "$*"; total=$((total + 1)); }

  root="$WORK/selftest"
  dwarf_dir="$root/Pastura.xcarchive/dSYMs/PasturaSharedEngine.framework.dSYM/Contents/Resources/DWARF"
  mkdir -p "$dwarf_dir"

  # A REAL Mach-O at the dSYM path, so the dwarfdump parsing is exercised
  # rather than stubbed. Any linked Mach-O carries an LC_UUID, so a one-line C
  # file suffices — no -g / dsymutil, and no multi-second compile.
  printf 'int main(void){return 0;}\n' > "$root/t.c"
  if ! xcrun clang -o "$dwarf_dir/PasturaSharedEngine" "$root/t.c" 2>/dev/null \
     && ! cc -o "$dwarf_dir/PasturaSharedEngine" "$root/t.c" 2>/dev/null; then
    die "self-test needs a working C compiler (xcrun clang / cc) to build the dSYM fixture."
  fi

  # A1 the archive check finds the dSYM and extracts a real UUID.
  uuid="$(check_kn_dsym_in_archive "$root/Pastura.xcarchive" 2>/dev/null)"
  case "$uuid" in
    *-*-*-*-*) ok "A1 archive check extracted a UUID ($uuid)" ;;
    *) bad "A1 expected a UUID, got '$uuid'" ;;
  esac

  # A2 an archive without the dSYM warns and still returns 0.
  mkdir -p "$root/empty.xcarchive"
  if out="$(check_kn_dsym_in_archive "$root/empty.xcarchive" 2>&1)"; then
    case "$out" in
      *"Kotlin/Native dSYM not found"*) ok "A2 absent dSYM warns without failing" ;;
      *) bad "A2 wrong output on an absent dSYM: $out" ;;
    esac
  else
    bad "A2 the archive check returned non-zero on an absent dSYM"
  fi

  # Fixture .ipa pair: one carrying the Symbols payload, one without it.
  up="$(printf '%s' "$uuid" | tr '[:lower:]' '[:upper:]')"
  mkdir -p "$root/good/Payload/Pastura.app" "$root/good/Symbols" "$root/bad/Payload/Pastura.app"
  : > "$root/good/Payload/Pastura.app/x"
  : > "$root/good/Symbols/$up.symbols"
  : > "$root/bad/Payload/Pastura.app/x"
  ( cd "$root/good" && zip -q -r "$root/good.ipa" Payload Symbols )
  ( cd "$root/bad" && zip -q -r "$root/bad.ipa" Payload )

  # A3 an .ipa carrying the payload passes with no warning.
  # shellcheck disable=SC2086  # deliberate split: one argument per UUID.
  if out="$(check_kn_symbols_in_ipa "$root/good.ipa" $uuid 2>&1)"; then
    case "$out" in
      *warning*) bad "A3 warned on an .ipa that has the symbols: $out" ;;
      *"$up.symbols present"*) ok "A3 .ipa carrying Symbols/<UUID>.symbols passes" ;;
      *) bad "A3 unexpected output: $out" ;;
    esac
  else
    bad "A3 the .ipa check returned non-zero on a good .ipa"
  fi

  # A4 an .ipa with no Symbols/ warns, names the UUID, and still returns 0.
  # shellcheck disable=SC2086  # deliberate split: one argument per UUID.
  if out="$(check_kn_symbols_in_ipa "$root/bad.ipa" $uuid 2>&1)"; then
    case "$out" in
      *"will NOT symbolicate"*) ok "A4 .ipa without Symbols/ warns and returns 0" ;;
      *) bad "A4 expected a symbolication warning, got: $out" ;;
    esac
  else
    bad "A4 the .ipa check returned non-zero instead of warning"
  fi

  # A5 no UUIDs (the archive check having failed) degrades to a skip — not a
  # vacuous pass, and not an abort.
  if out="$(check_kn_symbols_in_ipa "$root/good.ipa" 2>&1)"; then
    case "$out" in
      *skipped*) ok "A5 no UUIDs → skip warning, no failure" ;;
      *) bad "A5 expected a skip warning, got: $out" ;;
    esac
  else
    bad "A5 the .ipa check returned non-zero with no UUIDs"
  fi

  # A6 preserve_archive copies into a HOME-overridden destination.
  fake_home="$root/home"
  stamp="$(date +%Y-%m-%d)"
  mkdir -p "$fake_home"
  if out="$(HOME="$fake_home" preserve_archive "$root/Pastura.xcarchive" 9.9 123 2>&1)"; then
    if [ -f "$fake_home/Library/Developer/Xcode/Archives/$stamp/$APP_NAME 9.9+123.xcarchive/dSYMs/PasturaSharedEngine.framework.dSYM/Contents/Resources/DWARF/PasturaSharedEngine" ]; then
      ok "A6 preserve_archive copied the archive (dSYM included)"
    else
      bad "A6 preserve_archive reported success but copied nothing: $out"
    fi
  else
    bad "A6 preserve_archive returned non-zero on a writable destination"
  fi

  # A8 a file at the dSYM path that dwarfdump cannot read: the producer exits
  # non-zero, and the helper must still warn and return 0 — this is the arm
  # that would otherwise abort a finished archive under pipefail + set -e.
  mkdir -p "$root/junk.xcarchive/dSYMs/PasturaSharedEngine.framework.dSYM/Contents/Resources/DWARF"
  printf 'not a mach-o\n' > "$root/junk.xcarchive/dSYMs/PasturaSharedEngine.framework.dSYM/Contents/Resources/DWARF/PasturaSharedEngine"
  if out="$(check_kn_dsym_in_archive "$root/junk.xcarchive" 2>&1)"; then
    case "$out" in
      *"reported no UUID"*) ok "A8 unreadable dSYM warns without failing" ;;
      *) bad "A8 expected a no-UUID warning, got: $out" ;;
    esac
  else
    bad "A8 the archive check returned non-zero on an unreadable dSYM"
  fi

  # A7 an unwritable destination warns instead of exiting — the arm that pins
  # "never abort after the tag push".
  ro_home="$root/ro"
  mkdir -p "$ro_home"
  chmod 500 "$ro_home"
  if out="$(HOME="$ro_home" preserve_archive "$root/Pastura.xcarchive" 9.9 123 2>&1)"; then
    case "$out" in
      *"warning: archive copy failed"*) ok "A7 unwritable destination warns without exiting" ;;
      *) bad "A7 expected a copy-failure warning, got: $out" ;;
    esac
  else
    bad "A7 preserve_archive returned non-zero on an unwritable destination"
  fi
  chmod 700 "$ro_home"

  if [ "$fail" -ne 0 ]; then
    die "self-test FAILED ($total arms run)"
  fi
  printf 'self-test: passed (%s/%s arms)\n' "$total" "$total"
}

VERSION=""
DRY_RUN=0
NOTES_FILE=""
SELF_TEST=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version=*) VERSION="${1#*=}"; shift ;;
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    --notes-file=*) NOTES_FILE="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) sed -n '2,59p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
# --self-test runs BEFORE the --version requirement and before preflight: it
# exercises the helpers only, and must stay runnable on any checkout.
if [ "$SELF_TEST" -eq 1 ]; then
  self_test
  exit 0
fi

[ -n "$VERSION" ] || die "--version X.Y is required (the marketing version; X.Y.Z only for a hotfix)."
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*) : ;;
  *) die "--version must look like X.Y or X.Y.Z (got '$VERSION')." ;;
esac

# ── preflight ───────────────────────────────────────────────────────────
# Release only from a checkout that is identical to origin/<default> AND
# green on every required check. The required-check list is derived from
# the branch ruleset, NOT hardcoded: GitHub names a check-run after the
# job's `name:` field (not the job id), and the required set grows as CI
# jobs are added — a hardcoded list silently rots into a vacuous pass
# (ADR-014 § Preflight discipline).
preflight() {
  local owner_repo default_branch
  owner_repo="$(gh repo view --json nameWithOwner -q '.nameWithOwner')"
  default_branch="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')"
  log "Preflight: HEAD must equal origin/$default_branch and be CI-green"
  git fetch --quiet origin "$default_branch"
  local local_sha remote_sha
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(git rev-parse "origin/$default_branch")"
  [ "$local_sha" = "$remote_sha" ] \
    || die "HEAD ($local_sha) != origin/$default_branch ($remote_sha). Release only from a synced $default_branch."

  local req_file succ_file
  req_file="$WORK/required-contexts.txt"
  succ_file="$WORK/success-checkruns.txt"

  gh api "repos/$owner_repo/rules/branches/$default_branch" \
    --jq '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context] | .[]' \
    > "$req_file"
  # Non-empty guard: an empty required list would make the loop below pass
  # vacuously — refuse rather than release against no gate.
  [ -s "$req_file" ] \
    || die "No required_status_checks in the $default_branch ruleset — refusing to release without a green gate to verify."

  gh api "repos/$owner_repo/commits/$local_sha/check-runs" --paginate \
    --jq '.check_runs[] | select(.conclusion=="success") | .name' \
    > "$succ_file"

  local ctx missing=0 total=0
  while IFS= read -r ctx; do
    [ -n "$ctx" ] || continue
    total=$((total + 1))
    # -F fixed-string + -x whole-line: check-run names contain regex
    # metacharacters (§, parens, +).
    if grep -Fxq "$ctx" "$succ_file"; then
      log "  ✓ $ctx"
    else
      err "  ✗ required check not green: $ctx"
      missing=$((missing + 1))
    fi
  done < "$req_file"

  [ "$missing" -eq 0 ] \
    || die "$missing of $total required checks are not green on $local_sha."
  log "Preflight OK: all $total required checks green on $local_sha"
}

# ── release-notes ("What to Test") ───────────────────────────────────────
# Commit subjects since the previous release tag — the changelog FALLBACK
# used when no --notes-file is supplied (the /release skill normally passes
# reviewed tester-facing notes instead; see the NOTES source block below).
build_notes() {
  local last_tag
  last_tag="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  if [ -n "$last_tag" ]; then
    git log --pretty='- %s' "${last_tag}..HEAD"
  else
    git log --pretty='- %s' -n 20
  fi
}

preflight

BUILD="$(git rev-list --count HEAD)"
TAG="v${VERSION}+${BUILD}"

# NOTES source: an explicit --notes-file (the /release skill's reviewed,
# tester-facing "What to Test") wins; otherwise fall back to commit subjects.
# Validated here — BEFORE the --dry-run exit below — so a missing/empty notes
# file fails fast at dry-run rather than first at the irreversible upload.
# Guard the post-`cat` value (not just file size): `cat` strips trailing
# newlines, so a newline-only file collapses to empty and is rejected.
if [ -n "$NOTES_FILE" ]; then
  [ -f "$NOTES_FILE" ] || die "--notes-file not found: $NOTES_FILE"
  NOTES="$(cat "$NOTES_FILE")"
  [ -n "$NOTES" ] || die "--notes-file is empty: $NOTES_FILE"
else
  NOTES="$(build_notes)"
fi

log "Planned release: version $VERSION, build $BUILD, tag $TAG"

if [ "$DRY_RUN" -eq 1 ]; then
  log "--dry-run: stopping before ASC query / archive / upload (these need the"
  log "one-time bootstrap: ASC app record + API key + a signed-in Xcode Apple"
  log "ID that can sign for distribution (cloud-managed signing))."
  printf '\n--- What to Test (preview) ---\n%s\n' "$NOTES"
  exit 0
fi

# ── build-number guard ───────────────────────────────────────────────────
# Assert the computed build strictly exceeds the latest build already on
# TestFlight for this version, so a same-SHA re-cut fails here cleanly
# instead of as a mid-upload ASC duplicate rejection (ADR-014 § Build number).
log "Checking latest TestFlight build for $VERSION"
TF_OUT="$WORK/tf_build"
TF_BUILD_OUT="$TF_OUT" bundle exec fastlane ios latest_tf_build version:"$VERSION"
# Hard error if the lane ran but reported nothing — do NOT fall back to 0,
# which would pass the strict-exceeds guard trivially and defeat the
# duplicate-build protection.
[ -s "$TF_OUT" ] || die "fastlane latest_tf_build reported no build number (TF_BUILD_OUT empty)."
LATEST_TF="$(cat "$TF_OUT")"
[ "$BUILD" -gt "$LATEST_TF" ] \
  || die "build $BUILD does not exceed the latest TestFlight build $LATEST_TF for $VERSION. Add a commit or bump the version."

# ── archive ──────────────────────────────────────────────────────────────
ARCHIVE="$WORK/$APP_NAME.xcarchive"

# Stage the KMP umbrella the app target links (ADR-023 §6 Stage 5, #1635).
# This script calls xcodebuild directly, not via scripts/xcodebuild.sh, so
# it must stage on its own or the archive dies at link time with a bare
# "framework 'PasturaSharedEngine' not found". `--config release` so the
# archived K/N code is the optimized build rather than whatever the last
# dev run left staged (debug by default) — S5-3 (H5/H7) owns the fuller
# question of the release umbrella's provenance; this only keeps the
# pipeline runnable. The next wrapper run re-stages debug on its own.
log "Staging PasturaSharedEngine.xcframework (release config)"
scripts/kmp/assemble-xcframework.sh --config release \
  || die "KMP umbrella staging failed — see the script's output above (exit 1 = JDK 17+ / gradlew missing)."
# The staging script exits 0 as a deliberate no-op on a ref with no
# `shared/engine/build.gradle.kts`; on such a ref the archive would still die
# at link, so assert the bundle rather than trust the exit code.
[ -d "Pastura/Frameworks/PasturaSharedEngine.xcframework" ] \
  || die "staging reported success but Pastura/Frameworks/PasturaSharedEngine.xcframework is absent — is this ref pre-ADR-023 Stage 5?"

log "Archiving (Release, build $BUILD)"
# -allowProvisioningUpdates: distribution signing is cloud-managed (the cert's
# private key is not in the local keychain), so headless xcodebuild must be
# allowed to reach the Developer Portal to resolve the App Store profile and
# cloud cert. It authenticates via the signed-in Xcode Apple ID session, so
# that session must be live (an expired one fails with a portal/no-cert error;
# refresh via Xcode → Settings → Accounts). A future non-interactive CI run has
# no Xcode session and would additionally need -authenticationKeyID /
# -authenticationKeyIssuerID / -authenticationKeyPath pointing at an ASC key
# with App Manager+ role (the project's pastura-release key already qualifies)
# — out of scope for the local-first flow (ADR-014).
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD"

# Verify the archive's marketing version matches --version (the build uses
# the pbxproj MARKETING_VERSION; this catches an un-bumped app target).
ARCHIVE_PLIST="$ARCHIVE/Products/Applications/$APP_NAME.app/Info.plist"
ARCHIVE_MV="$(plutil -extract CFBundleShortVersionString raw "$ARCHIVE_PLIST" 2>/dev/null || true)"
[ "$ARCHIVE_MV" = "$VERSION" ] \
  || die "archive marketing version ($ARCHIVE_MV) != --version ($VERSION). Bump the app target's MARKETING_VERSION."

# ── ADR-005 §8.5 symbol guard on the ARCHIVED binary ─────────────────────
# CI checks an unsigned build product; the archived/signed binary is what
# ships, so re-run the guard here. Portable find-into-var (bash 3.2).
log "Verifying no Ollama symbols in the archived binary (ADR-005 §8.5)"
APP_BIN=""
while IFS= read -r -d '' f; do APP_BIN="$f"; done \
  < <(find "$ARCHIVE/Products/Applications" -type f -path "*/$APP_NAME.app/$APP_NAME" -print0)
[ -n "$APP_BIN" ] || die "archived app binary not found under $ARCHIVE"
# Capture, don't `| grep -iq` — `-q` exits early, the still-writing upstream
# SIGPIPEs, and `pipefail` turns a MATCH into a pass, so this guard was working
# on symbol ordering rather than on the check (#1498). `nm -a` on the app
# binary is megabytes, far past any pipe buffer.
# `.claude/rules/ci-workflows.md` § "Rule 3".
#
# `|| [ $? -eq 1 ]` and not `|| true`: exit >=2 (broken pattern) must abort the
# release, not report a clean binary. The CI sibling in .github/workflows/ci.yml
# checks the unsigned build; this copy is the one that gates what ships.
LEAKED="$(nm -a "$APP_BIN" | xcrun swift-demangle | { grep -i ollama || [ $? -eq 1 ]; })"
if [ -n "$LEAKED" ]; then
  printf '%s\n' "$LEAKED" >&2
  die "Ollama symbols leaked into the Release archive (ADR-005 §8.5)."
fi
log "  ✓ zero Ollama symbols"

# ── ADR-023 §6 S5-3 (H7): Kotlin/Native dSYM in the archive ──────────────
log "Checking the Kotlin/Native dSYM in the archive (ADR-023 §6 S5-3, H7)"
KN_UUIDS="$(check_kn_dsym_in_archive "$ARCHIVE" || true)"

# ── export ───────────────────────────────────────────────────────────────
EXPORT_DIR="$WORK/export"
PLIST="$WORK/exportOptions.plist"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<!-- Xcode's default, made explicit: H7 depends on the .ipa's Symbols/
	     payload reaching ASC so Kotlin/Native frames symbolicate there. -->
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST_EOF

log "Exporting .ipa (method app-store-connect)"
# -allowProvisioningUpdates: same reason as the archive step — the export
# re-signs with the cloud-managed distribution cert, which headless xcodebuild
# can only resolve when allowed to contact the portal.
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates

IPA=""
while IFS= read -r -d '' f; do IPA="$f"; done \
  < <(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print0)
[ -n "$IPA" ] || die "no .ipa produced under $EXPORT_DIR"

# ── ADR-023 §6 S5-3 (H7): ASC symbol payload for the K/N dSYM ────────────
log "Checking the exported .ipa's ASC symbol payload (ADR-023 §6 S5-3, H7)"
# shellcheck disable=SC2086  # deliberate word splitting: one argument per UUID.
check_kn_symbols_in_ipa "$IPA" $KN_UUIDS

# ── upload ───────────────────────────────────────────────────────────────
log "Uploading to TestFlight"
if bundle exec fastlane ios upload ipa:"$IPA" changelog:"$NOTES"; then
  # ── tag (only after a successful upload) ──────────────────────────────
  log "Upload succeeded — tagging $TAG"
  git tag -a "$TAG" -m "Release $VERSION (build $BUILD)"
  git push origin "$TAG"
  preserve_archive "$ARCHIVE" "$VERSION" "$BUILD"
  log "Done: $TAG pushed; build $BUILD is processing on TestFlight."
else
  die "upload failed — no tag created. Fix and re-run (the build number is unchanged; add a commit if ASC already ingested this build)."
fi
