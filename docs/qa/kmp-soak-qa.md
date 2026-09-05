# Shared-Engine Soak Runbook (ADR-023 §6 S5-4)

> One TestFlight soak cycle for the S5-4 flag-gated Kotlin run path
> ([#1681](https://github.com/tyabu12/pastura/issues/1681)). This runbook mirrors
> `docs/qa/h7-symbolication-qa.md` in structure — read that one first if this is your first
> operator cycle on this project.

## Purpose

S5-4 landed a Debug/TestFlight-only toggle (`FeatureFlags.sharedEngineEnabled`, Settings ›
Diagnostics) that selects the Kotlin `PasturaSharedEngine` run path for **fresh** simulation runs.
Before Decision 6 (iii) can discharge, one operator soak cycle on a real TestFlight build must
exercise the Kotlin engine end to end — including pause/resume, backgrounding, and an app-kill
mid-run — and confirm the `ja` localization surface renders through the Kotlin `appleMain` actual
rather than falling back to its key. This is an operator cycle: nothing here runs unattended, and
nothing here is checked by CI.

## Prerequisites

- `main` at or after the S5-4 switch PR (#1681): `FeatureFlags.sharedEngineEnabled`, the
  Diagnostics Toggle + sample-message row, `SharedEngineDiagnostics.swift`, and the
  `SimulationViewModel` Kotlin run-path plumbing.
- A `/release` TestFlight cut carrying that PR, installed on a real device (the simulator cannot
  stand in for backgrounding / app-kill behavior).
- A device set to Japanese — either the device's own language, or a per-app language override
  (Settings → Pastura → Language) if the device stays in English for other reasons.
- The S5-3 reveal gesture is still present: the version row on the About screen still needs five
  taps to reveal Diagnostics. If it has been removed, this runbook does not apply — check whether
  S5-5 has already landed.

## What counts as evidence

| Check | Evidence | Not evidence |
|---|---|---|
| A run completes end-to-end on the Kotlin engine | The simulation log fills turn by turn and the result card is shown at the end, toggle left on for the whole run | A run started with the toggle off, or one that errors out before the result card |
| Pause → resume mid-run | Tapping pause stops new turns; tapping resume continues the same run to completion | A pause that never resumes (that only exercises `pause()`, not the full cycle) |
| Background → foreground mid-run | Lock the screen or switch apps mid-run, then return — the run resumes and completes | Backgrounding after the run has already finished |
| Kill-and-resume via the Swift runner | Start a run on the Kotlin engine, background it, force-quit the app, reopen from the Home screen — the app offers to resume the in-progress simulation and it completes on the **Swift** runner (the Kotlin engine has no resume-from-state — ADR-023 §6 S5-4) | Expecting the resumed run to still be on the Kotlin engine — it is not, by design |
| `ja` localization surface | Settings › Diagnostics shows the sample rendered message in Japanese: 「無効な YAML 形式です」 | The same row in English — that means the `appleMain` `localizedFormat` actual fell back to the untranslated key, and is itself a finding to record, not a pass |
| No crash | App Store Connect's crash view shows nothing new for this build during the cycle | A crash you cannot attribute to the build (check the build number in the crash report first) |
| **Does NOT count as evidence** | — | Simulator runs (no real backgrounding/app-kill signal); Debug builds (App Store Connect's crash view only carries TestFlight/App Store builds) |

## Steps

1. **Confirm the build.** Note the version/build number of the TestFlight cut under test.
2. **Reveal Diagnostics.** Settings → About → tap the version row five times → the Diagnostics
   section appears.
3. **Enable the switch.** Diagnostics → toggle "Run simulations on the shared engine" on.
4. **Run the bundled presets.** Start each of the following from the gallery and let it run to
   completion, confirming the log fills and the result card appears (`Pastura/Pastura/Resources/Presets/`).
   Each preset has an `_en.yaml` twin; on a Japanese device the gallery shows the `ja` titles, so
   run the `ja` variants (no `_en` suffix) below.
   - `target_score_race.yaml` — exercises the `conditional` phase type.
   - `word_wolf.yaml` — vote-heavy (elimination + majority vote), also exercises `conditional` and
     `event_inject`.
   - `last_fable.yaml` — exercises `event_inject` on a different scenario shape.
   - `prisoners_dilemma.yaml` — the only preset exercising `pairing` + the ADR-027
     `pairwise_payoff` scoring logic.
5. **Pause/resume cycle.** On one of the three runs above, pause mid-run and resume — confirm it
   continues on the Kotlin engine and completes.
6. **Background cycle.** On another run, lock the screen (or switch to another app) mid-run and
   return after at least 30 seconds — confirm the run resumes and completes.
7. **Kill-and-resume cycle.** Start a run, background it, then force-quit the app from the app
   switcher. Reopen from the Home screen icon (not from a notification or deep link) and confirm
   the app offers to resume the in-progress simulation. Let it finish — this leg runs on the Swift
   runner, which is expected (Step "Kill-and-resume via the Swift runner" above).
8. **Check the `ja` row.** With the device in Japanese, open Diagnostics and read the sample
   rendered message row. Confirm it reads 「無効な YAML 形式です」, not the English fallback.
9. **Check App Store Connect.** After the cycle, check the build's crash view in App Store Connect
   for anything new.
10. **Record on [#501](https://github.com/tyabu12/pastura/issues/501)** as one comment:
    - Build number and device model.
    - A per-preset outcome table (preset name → completed / failed, and which of pause / background
      / kill-resume was exercised on it).
    - The `ja` screenshot description (or the screenshot itself) and whether it read Japanese or
      fell back to English.
    - The App Store Connect crash-view check result.

## Follow-up PR after the cycle

Once the soak evidence is on #501:

- ADR-023 §6 S5-4 amendment: the soak outcome, with a link to the #501 evidence comment.
- Decision 6 (iii) discharged (or the specific finding recorded, if the cycle surfaced one).
- `docs/kmp-migration-status.md` Stage-5 row and prose bullet updated to reflect the soak as done.
- Open S5-5 planning (code-merge and close-out, including the H7 probe deletion's ordering
  constraint against the next App Store submission).

## If a run fails on the Kotlin engine

The Swift runner is one toggle away — turn "Run simulations on the shared engine" off in
Diagnostics and the app falls back to the existing, shipped run path; no user data or in-progress
run needs to be discarded to recover.

Before turning it off, capture what you can:

- The `run() engine=kotlin` log line (Console.app, process `Pastura`) marking which engine the run
  selected.
- The `ErrorEvent` (or the last few log lines before the failure) from the simulation log.
- The preset that was running and how far it got (which phase/round).

File the finding against [#501](https://github.com/tyabu12/pastura/issues/501) with those details.
The flag defaults to off, so App Store users are unaffected by a failure found during this cycle —
there is no user-facing urgency, but do not let the finding go unrecorded before re-attempting the
cycle.
