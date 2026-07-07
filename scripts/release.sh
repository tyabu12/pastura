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
#   export     → xcodebuild -exportArchive, method app-store, with an
#                exportOptions.plist generated at cut time (never committed)
#   upload     → fastlane upload_to_testflight
#   tag        → annotated tag v<version>+<build>, pushed ONLY after the
#                upload succeeds (a failed upload leaves no dangling tag)
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
#   scripts/release.sh --version X.Y.Z [--dry-run]
#
#   --dry-run   Run preflight + build-number computation and print the
#               planned release, then stop BEFORE the ASC query, archive,
#               and upload (those require the bootstrap above). Safe to run
#               on any CI-green main checkout.
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

VERSION=""
DRY_RUN=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version=*) VERSION="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[ -n "$VERSION" ] || die "--version X.Y.Z is required (the marketing/semver version)."
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*) : ;;
  *) die "--version must look like X.Y.Z (got '$VERSION')." ;;
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
# Commit subjects since the previous release tag; passed to TestFlight as
# the changelog.
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
NOTES="$(build_notes)"

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
if nm -a "$APP_BIN" | xcrun swift-demangle | grep -iq ollama; then
  die "Ollama symbols leaked into the Release archive (ADR-005 §8.5)."
fi
log "  ✓ zero Ollama symbols"

# ── export ───────────────────────────────────────────────────────────────
EXPORT_DIR="$WORK/export"
PLIST="$WORK/exportOptions.plist"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST_EOF

log "Exporting .ipa (method app-store)"
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

# ── upload ───────────────────────────────────────────────────────────────
log "Uploading to TestFlight"
if bundle exec fastlane ios upload ipa:"$IPA" changelog:"$NOTES"; then
  # ── tag (only after a successful upload) ──────────────────────────────
  log "Upload succeeded — tagging $TAG"
  git tag -a "$TAG" -m "Release $VERSION (build $BUILD)"
  git push origin "$TAG"
  log "Done: $TAG pushed; build $BUILD is processing on TestFlight."
else
  die "upload failed — no tag created. Fix and re-run (the build number is unchanged; add a commit if ASC already ingested this build)."
fi
