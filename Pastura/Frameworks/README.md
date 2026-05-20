# Pastura/Frameworks/

Drop location for `PasturaShared.xcframework`, the iOS-side artifact of
the KMP Models layer spike (Issue #220, ADR-004 Draft).

## Why this directory exists

`Pastura.xcodeproj` references `PasturaShared.xcframework` at this path
via its Framework Search Paths (`$(SRCROOT)/Frameworks`). The
xcframework itself is **gitignored** (`.gitignore`:
`Pastura/Frameworks/*.xcframework`) because it is reproducible from
Kotlin source in `shared/models/`.

The README is **not** gitignored — the pattern is xcframework-specific so
this file remains discoverable in a fresh clone, documenting how to
produce the artifact.

## First-time setup

After cloning the repo (and once per `git clean -fdx`):

```bash
./scripts/setup.sh                          # one-time: git hooks + KMP xcframework
```

`setup.sh` invokes `scripts/kmp/assemble-xcframework.sh --if-missing`
internally — succeeds silently if JDK 17 is installed, prints a warning
and continues if JDK 17 is missing (iOS-only contributors are not blocked,
but Pastura.app builds will fail at link until the framework is present).

## Daily workflow

The git `pre-commit` hook runs `assemble-xcframework.sh --if-missing` as
step 0. On Swift-only commits (no `shared/` changes), Gradle's UP-TO-DATE
check provides a ~1-2 second fast path. On KMP-touching commits, the full
assemble runs (typically 30 s warm, several minutes cold).

To force-rebuild (e.g., after adding a Kotlin export that triggers
"undefined symbol" at the Xcode link step):

```bash
./scripts/kmp/assemble-xcframework.sh       # no flag, always rebuilds
```

## Requirements

- **JDK 17 or newer** — install via `brew install --cask temurin@17`
  (or any later LTS — JDK 21 works). Versions below 17 are rejected
  with an actionable message. CI pins JDK 17 for parity.
- **gradlew** — checked into the repo at the root (no separate Gradle
  install required).
- **Xcode 26.x** — the iOS-side consumer; Kotlin/Native + Apple SDKs are
  resolved by Gradle from `xcrun`.

## CI coverage gap

CI runs `assemblePasturaSharedXCFramework` in the `kmp-build-test` job
(gated to the long-lived `feature/kmp-spike-models` integration branch).
Downstream Pastura xcodebuild jobs (`lint-and-test`, `ui-test`,
`release-build`) consume the framework via `actions/download-artifact`
when `kmp-build-test` produced one.

**What CI does NOT validate:**

- **Embed & Sign correctness** for App Store submission. `release-build`
  runs with `CODE_SIGNING_ALLOWED=NO`, which bypasses the codesign step.
  K/N XCFrameworks differ from Swift Packages in their embed plumbing;
  unsigned-archive CI does not exercise the path that ASC validates.
- **H5 ASC archive dry-run** — Issue #220 Tier 1 H5 ("Archive builds and
  uploads to ASC successfully") is deferred to W3+ / W4. Until H5 lands,
  treat Embed & Sign correctness as unverified.

**Do not infer ASC-readiness from green CI.** Future Tier 1 validation
runs through ASC submission, not local archive.

## W6 merge-PR caveat

When the integration branch eventually merges into `main` (Issue #220 W6
GO PR), the `kmp-build-test` job's gate (`base_ref ==
'feature/kmp-spike-models'`) will not match (the merge PR has `base_ref ==
'main'`). Downstream jobs would then run with the merged pbxproj
referencing `Pastura/Frameworks/PasturaShared.xcframework` but no
artifact from `kmp-build-test` — link failure at `xcodebuild build`.

**W6 plan must address one of:**

1. Extend `kmp-build-test`'s `if:` to also fire when `base_ref == 'main'
   && head_ref == 'feature/kmp-spike-models'` (covers the merge PR).
2. Add a pre-merge step that stages the xcframework before the merge runs.
3. Restructure so `assemblePasturaSharedXCFramework` becomes
   unconditional on `main` once integration lands.

Track this in the W6 merge plan; do not let merge-day pressure surface it
the first time.
