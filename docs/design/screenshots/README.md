# Design-review screenshots

Generated PNGs of the app's major screens, for design review by humans
and agents. **The PNGs are gitignored** — regenerate on demand:

```bash
scripts/ui-tour.sh
```

The script runs `ScreenshotTourTests` (an XCUITest tour in `--ui-test`
launch mode: in-memory DB, `MockLLMService`, `StubGalleryService`,
deterministic seed content) on the UDID-pinned simulator and extracts
the attachments here. Requires `jq`. Takes a few minutes including the
build. Review-only capture — no assertion against stored references
(see the ADR-009 note); excluded from CI via `-skip-testing` in
`ci.yml`.

## Covered screens

| File | Screen |
|------|--------|
| `01-home.png` | Home (scenario list) |
| `02-scenario-detail.png` | Scenario detail (seeded scenario) |
| `03-editor.png` | Scenario editor (new scenario) |
| `04-shared-scenarios.png` | Shared Scenarios gallery |
| `05-gallery-detail.png` | Gallery scenario detail |
| `06-settings.png` | Settings |
| `07-results.png` | Past Results list (seeded fixture) |
| `08-result-detail.png` | Result detail timeline (seeded fixture) |
| `09-home-resume.png` | Home with the paused-run resume card |
| `10-home-empty.png` | Home empty state (no local scenarios) |
| `11-results-empty.png` | Past Results empty state (no results) |
| `12-search-no-match.png` | Browse search with no matching query |
| `13-gallery-empty.png` | Browse gallery loaded but empty ("No scenarios available yet") |
| `14-gallery-offline.png` | Browse gallery offline / load failure ("Gallery Unavailable") |

Rows 10–14 are the empty / error surfaces (#811) the ui-refine L5 (empty /
error / edge) and L6 (copy) lenses critique — seeded via
`--ui-test-seed-empty-inventory` / `--ui-test-seed-empty-gallery` /
`--ui-test-seed-gallery-offline` (see `ScreenshotTourTests`).

Content is fixture-driven (`StubScenarioSeeder` / `StubResultSeeder` /
`StubGalleryService`), so layouts are representative but copy is test
data — review structure, spacing, and tokens here; review real copy in
the app.

Where each screen sits in the navigation graph:
[`../navigation-map.md`](../navigation-map.md) (generated). Its
"Screenshot tour" table is derived from `ScreenshotTourTests` and lists
these stops in tour order with their wait anchors and how each is
reached (launch root / tab switch / push); the Mermaid graph above it
shows the root-stack push edges.

## Adding a screen

Add a tour stop in
`Pastura/PasturaUITests/ScreenshotTourTests.swift` (navigate, then
`capture(app, name: "NN-name", anchorId: ...)` on an element that only
exists once the screen has loaded), then add a row to the table above.

## Dark set

```bash
scripts/ui-tour.sh --dark     # → docs/design/screenshots/dark/
```

Same tour, same filenames, second directory — the light set's names are
referenced by name from this README, `../navigation-map.md` and the
`ui-refine` skill, so they stay put. Opt-in rather than automatic: each
appearance is a full `xcodebuild test` pass. The simulator's prior
appearance is restored on exit, so a `--dark` run does not leave the
device dark for `scripts/motion-capture.sh`, which is deliberately
device-following.

**What the dark set is for, and what it is not.** It is for reviewing
typography, spacing and overall mood in the dark palette. It is **not**
dark-mode QA coverage. Against the six classes in
`../../qa/dark-mode-qa.md` § "What is actually at risk":

| Class | On this tour? |
|---|---|
| A. Fixed tokens (`GameHeader` meta row) | No — Simulation and Demo replay are both off-tour |
| B. Materials | **2 of §3's 11 sites**: the ScenarioDetail action bar (stop `02`) and the Editor capsule (stop `03`). A material re-rendering wrong in dark is a static property, so these two captures do show it |
| C. Fixed-appearance exports (share card) | No — never rendered by the tour |
| D. Non-SwiftUI | No. §1's launch/splash precede the tour; §5's `UINavigationBar` proxy *is* on screen at stops `02`/`03`/`05`/`08`, but it bakes at launch under the pinned appearance, and its failure mode needs background → switch → return, which no fresh-launch capture reaches |
| E. Occlusion layers (scrim) | No — the model-load scrim is Simulation-only |
| F. A screen with no ground at all | **Yes — stops `11` and `14`**, the empty arms of `ResultsView` and `SharedScenariosListView`: two of the five sites [#1354](https://github.com/tyabu12/pastura/issues/1354) tracks, which owns the per-site mechanism. Stops `10`, `12` and `13` look like F and are not — each renders under a ground. F is the one class a static capture reaches at all, since the failure is an **absent** modifier that light hides and dark exposes. Both reachable instances are already filed — **do not re-report** |

So B and F are the covered classes — B partially, F only at stops whose
defects are already tracked — and the other four are not. Everything else
the dark set shows is the ordinary paired-token surfaces, which gate 1
closed by measurement and `DesignTokensTests` asserts for all 67 pairs.
Treat a finding here as a design observation, not as a defect the device
walkthrough would have caught.

**The two sets drift independently.** Each is refreshed only by its own
invocation, both are gitignored so no diff reveals staleness, and they
share filenames — `01-home.png` exists in both. Re-run both before any
side-by-side comparison, or you may be attributing a months-old delta to
the appearance.

**`ui-refine` stays light-only — decided, not pending**
([#1345](https://github.com/tyabu12/pastura/issues/1345)). Its capture glob is
single-level, so it never reaches `dark/`. Wiring it up was planned, reviewed
and declined: six of the seven lenses cite a § 2 anchor, but only **L1** cites
a *dark-specific* one (§ 2.9), and L4 is excluded outright since
`motion-capture.sh` exposes no appearance flag. The rest read their colour
anchors through questions that resolve the same once the paired tokens invert
(`../ui-refine/lenses.md` has the per-lens anchors), so a dark arm would
restate the light finding on six runs in seven — the repetition that skill's
ledger exists to stop. The one appearance-specific failure, a token that fails
to invert, is a **defect**, which ui-refine declares a Non-goal
(`../ui-refine/README.md` § "What it is — and is NOT"); it belongs to
`DesignTokensTests`, the device walkthrough and #1354.

**Re-arm** on either, both countable:

1. A human skims the current dark set and files a finding that is not already
   tracked and that cites a `../design-system.md` anchor
   (`../../qa/dark-mode-qa.md` § "While you are here: skim the dark review
   set" hosts that step — nothing else fires this condition).
2. The lens catalog gains, or re-scopes an existing lens into, an
   appearance-bound lens other than L1 (`../ui-refine/lenses.md`
   § "Adding / reordering lenses" points back here).

## Deferred (not yet captured)

- **ModelSelection / ModelDownload** — `--ui-test` mode bypasses the
  model-download flow entirely (straight to `.ready`); capturing these
  needs a dedicated launch-argument path.
- **Mid-run Simulation** — `MockLLMService` launches with an empty
  response queue under `--ui-test`, so a running simulation errors on
  first inference; capturing a live turn needs canned-response seeding
  via a launch argument.
- **Dynamic Type / ja locale variants** — single configuration only
  for now; variants multiply runtime and can be added per-screen when
  a review needs them.

## Animations

These are still screens. For *motion* review — the launch splash, and the
bubble-entrance / DL-dot animations that share the reachability blockers
noted above — see [`../motion/README.md`](../motion/README.md)
(`scripts/motion-capture.sh`): filmstrips + frame sequences captured the
same gitignored, local-only way.
