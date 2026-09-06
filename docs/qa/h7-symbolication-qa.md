# H5 / H7 Distribution-Verification Runbook (ADR-023 §6 S5-3)

> **Executed 2026-09-05 — `v1.3+886`, both halves PASS** (evidence: [#501](https://github.com/tyabu12/pastura/issues/501#issuecomment-5550162180)), ADR-004 §11. Kept as the reference procedure; the two `release.sh` checks below are now fail-fast, not warnings.
>
> **Historical record — cannot be re-run as written.** The reveal gesture, the
> Diagnostics section, and the crash-trigger button this runbook drives were
> all deleted at ADR-023 S5-5 ([#1685](https://github.com/tyabu12/pastura/issues/1685)). The body below is left unedited.

Operator steps for the one TestFlight cycle that executes **H5** (an App Store
Connect upload of a build carrying the Kotlin/Native `PasturaSharedEngine`
umbrella) and **H7** (a Kotlin crash from that build symbolicated through the
K/N dSYM). Both are ADR-004 §9.2's deferred launch-prep actions; H7 is also
ADR-023 Decision 6 (ii), a hard precondition of the S5-4 engine switch.

Nothing here is automated end-to-end on purpose: the cycle spends a real
TestFlight build number, and the two properties it measures can only be
observed on Apple's side. What *is* mechanical lives in `scripts/release.sh`
(`--self-test` exercises it against fixtures).

## Prerequisites

- `main` at or after the S5-3 prerequisites PR (#1673): the Kotlin
  `H7CrashProbe`, `App/KMP/H7CrashTrigger.swift`, the Settings Diagnostics
  section, and the release-script K/N dSYM checks.
- The ADR-014 bootstrap (ASC app record, API key in the environment, a signed-in
  Xcode Apple ID) — `scripts/release.sh --dry-run` passes.
- A TestFlight device that can install the build. The simulator cannot run
  this: H7 needs a real crash report to propagate to ASC.

## What each half asserts — and what does not count as evidence

| Half | Property | Evidence | Not evidence |
|---|---|---|---|
| H5 | ASC processes a build carrying the K/N XCFramework without an invalid-binary rejection (risk R7) | `bundle exec fastlane ios upload` returns success — the lane waits for processing (`skip_waiting_for_build_processing: false`), so the release tag being pushed **is** the H5 verdict | A local archive succeeding; CI's `CODE_SIGNING_ALLOWED=NO` release build |
| H7 (ASC half) | The K/N dSYM uploaded **with the build** symbolicates the Kotlin frames | The crash in **App Store Connect → TestFlight → Crashes** (or Xcode Organizer → Crashes *with the local archive copy moved away*) shows `com.pastura.engine.H7CrashProbe` / `kfun:` frames with function names | Organizer symbolicating while `~/Library/Developer/Xcode/Archives/` still holds the archive copy — that resolves against the **local** dSYM and proves nothing about the upload |
| H7 (local half) | The archive's K/N dSYM matches the shipped binary | Organizer → Crashes symbolicates the same report with the archive copy present | — (this half is a fallback for field crashes, not the ADR-004 property) |

**Pass criterion for H7 is one symbolicated Kotlin frame**, not two. The
Kotlin probe routes through a private helper so a second frame *may* appear,
but the release build is optimized and K/N may inline it; ADR-004 §9.2 asks
for "symbolicated frames via K/N dSYM", which one named `H7CrashProbe.crash`
frame satisfies.

## Steps

1. **Cut the build.** Run `/release` (or `scripts/release.sh --version X.Y
   --notes-file …`). Read the two checks in the output — both are now
   **fail-fast**, aborting the release before the upload:
   - `kn-dsym`: the xcarchive's `dSYMs/` holds
     `PasturaSharedEngine.framework.dSYM`; the script logs its UUID(s).
   - `kn-symbols`: the exported `.ipa` carries a `Symbols/<UUID>.symbols`
     entry for each of those UUIDs. **If either check dies, the script stops
     before upload — the ASC half of H7 cannot pass this cycle** (see "If the
     upload lacks the K/N symbols" below for what to read and do next).
   - The tag push is the H5 verdict (table above). Record the tag and the
     build number.
   - After the tag, the script copies the xcarchive to
     `~/Library/Developer/Xcode/Archives/<date>/` (non-fatal). Note the path.
2. **Install the TestFlight build** on the device once processing completes.
3. **Reveal the Diagnostics section.** Settings → scroll to **About** → tap the
   version row **five times**. A **Diagnostics** section appears above About.
   (Debug builds can also `defaults write app.pastura.Pastura.dev
   h7CrashProbeEnabled -bool true`; TestFlight has no such path — the gesture
   is the only one.) If nothing happens, the channel gate resolved `false`:
   connect the device and read Console.app (process `Pastura`, category
   `BuildChannel`) — since #1677 the gate falls back to the receipt file name
   when `AppTransaction.shared` throws, and that log line carries the error
   and the receipt name it saw (`sandboxReceipt` expected on TestFlight).
4. **Fire the probe.** Diagnostics → *Crash the shared engine* → confirm
   *Crash*. The app terminates immediately. Relaunch it once so the crash
   report is submitted (TestFlight submits on next launch; the device must
   have Share With App Developers / crash sharing enabled for TestFlight
   builds — the TestFlight app prompts for this on first install).
5. **Wait.** Crash-report propagation to ASC takes from minutes to hours.
6. **Read the ASC half first.** App Store Connect → TestFlight → the build →
   Crashes (or Xcode Organizer → Crashes *after* moving the archive copy out of
   `~/Library/Developer/Xcode/Archives/`). Open the report. Expect the crashed
   thread to show the K/N uncaught-exception path: `kfun:kotlin.Throwable…` /
   `ThrowException` / `kfun:com.pastura.engine.H7CrashProbe#crash(kotlin.String)`.
   **PASS** = at least one `com.pastura.engine.H7CrashProbe` frame carries a
   function name rather than a bare address. Capture the frame lines.
7. **Read the local half.** Put the archive copy back; Organizer → Crashes
   should symbolicate the same report. This is the field-crash fallback,
   recorded for completeness.
8. **Record on #501** (one comment): tag, build number, the `kn-dsym` /
   `kn-symbols` lines verbatim, the ASC-half frame lines verbatim, and the
   local-half result. Then open the follow-up docs PR (below).

## Follow-up PR after the cycle

All four are tracked by the close-out issue #1679; the list stays as the record of what the cycle owed:

- ADR-004 §9.2 amendment: H5 and H7 outcomes; Conditional GO → GO, or voided
  on R7 / non-symbolicating frames (the two named voiding conditions).
- ADR-023 §6: Decision 6 (ii) discharged; the S5-3 bullet marked landed.
- `scripts/release.sh`: promote `kn-dsym` / `kn-symbols` from warnings to
  `die` now that the path has been observed once.
- `docs/kmp-migration-status.md` Stage-5 paragraph.

The probe itself (Kotlin `H7CrashProbe`, `H7CrashTrigger`, the Diagnostics
section and its state, `FeatureFlags.h7CrashProbeEnabled`, the five H7 catalog
keys — `About` stays with its section —, `settings.h7CrashButton`) is deleted in **S5-5**, and that deletion must
land **before the next App Store submission**: the reveal gesture is gated on
the `.sandbox` StoreKit environment, which an App Review install also reports, and a deliberate
crash reachable by a reviewer is a Guideline 2.1 rejection.

## If the upload lacks the K/N symbols (`kn-symbols` died)

The archive had the dSYM but the exported `.ipa` did not carry its
`.symbols`, so `kn-symbols` died and the script stopped before upload — no
build shipped without symbols. App Store Connect symbolicates TestFlight
crashes only from the symbols packaged into the upload itself — there is no
separate "upload a dSYM" path for TestFlight builds — so the fix is on the
export side (`-exportArchive` with `uploadSymbols` true, which the script
makes explicit; check whether Xcode drops symbols for an *embedded prebuilt*
XCFramework as opposed to its own build products). Do not spend a second
cycle guessing: inspect the export directory and the `.ipa` listing from the
failed run, fix the export, and re-run `scripts/release.sh` — record the
finding on #501 if it recurs.

## If the frames do not symbolicate

Confirm the UUID in the crash report's binary-images list for
`PasturaSharedEngine` equals the `kn-dsym` UUID the script logged. A mismatch
means the staged XCFramework at archive time was not the one linked (the
`assemble-xcframework.sh --config release` step in `release.sh` exists to
prevent this). If the UUIDs match and the frames are still bare addresses,
that is the ADR-004 §9.2 voiding condition: record it and re-open the ADR-004
GO on #501 rather than working around it.
