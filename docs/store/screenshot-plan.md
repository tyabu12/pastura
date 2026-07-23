# App Store screenshot plan

> Capture plan + pipeline for the 1.0 submission. PNGs are **not committed** —
> `scripts/store-shots.sh` renders them into the gitignored
> `docs/store/screenshots/{en,ja}/`. This file is the committed artifact.

## Scope decision — iPhone only

1.0 ships **iPhone-only** (`TARGETED_DEVICE_FAMILY = "1"`). Consequence for
screenshots: **only the 6.9″ iPhone set is required**; the 13″ iPad set is not.

> ⚠️ **Ordering dependency**: the code PR that narrows `TARGETED_DEVICE_FAMILY`
> from `"1,2"` to `"1"` **must merge before the release archive**. Until then the
> build is still universal and ASC would ask for iPad screenshots. Rationale for
> iPhone-only (device-QA on iPad not possible; `UIRequiredDeviceCapabilities`
> narrowing is a one-way door on the *keep-iPad* side): see #233.

## Required sizes (ASC, 2026)

Apple requires only the **largest display per family**, then auto-scales down to
smaller devices. iPhone-only ⇒ one size:

| Family | Required source size | Device that renders it |
|---|---|---|
| iPhone 6.9″ | **1320 × 2868** px portrait | `iPhone 17 Pro Max` sim (the only 6.9″ device available locally) |
| iPad 13″ | — not required (iPhone-only) | — |

Format rules: **PNG or JPEG, RGB, no alpha channel, exact pixel dimensions
(no off-by-one tolerance), 1–10 per size.** `store-shots.sh` asserts
1320×2868 + no-alpha on every output (and flattens alpha if a screenshot ever
carries it).

## The pipeline — `scripts/store-shots.sh`

One command produces the whole set:

```bash
scripts/store-shots.sh
```

It pins the 6.9″ sim, runs `PasturaUITests/StoreScreenshotTests`, extracts the
PNG attachments, routes them into `docs/store/screenshots/{en,ja}/`, and
verifies each is exactly 1320×2868 with no alpha. Requires `jq` and an available
`iPhone 17 Pro Max` simulator. The capture is deterministic — the `--ui-test`
harness (in-memory DB, `MockLLMService`, `StubGalleryService`, seeded content)
means **no 3 GB model download** is needed.

`StoreScreenshotTests` captures both locales in one run: it relaunches the app
per locale with `-AppleLanguages`/`-AppleLocale`, and switches tabs by
`rootTab.*` accessibility identifier (not the localized tab label) so the ja
walk resolves. Attachments are named `{locale}-NN-screen`; the script routes by
the `{locale}-` prefix.

### Seeded content is per-locale

Localized UI chrome is not enough — the *seeded data* has to match the locale,
or a ja capture shows Japanese chrome around English content. Two independent
seams carry this, and both must be checked when adding a shot:

| Surface | Seam | ja | en |
|---|---|---|---|
| Shot 01 transcript | `StoreScreenshotTests.StoreLocale.resultSeedArgument` → `PasturaApp.resultSeedFixture()` | `--ui-test-seed-results-wordwolf` (verbatim Japanese run) | `--ui-test-seed-results` (Alice / Bob) |
| Shots 02 / 05 row copy | `StubScenarioSeeder` + `StubScenarioSeeder+Localized.swift`, selected by `LocaleResolver.deviceDefault()` | Japanese names + descriptions | English |

The row-copy seam deliberately reads the **device locale** rather than taking a
launch argument of its own: the capture already passes `-AppleLanguages`, and a
second switch that has to agree with it silently produces mismatched captures
when it doesn't. Ids, `agents`, `rounds`, and phase shape are identical across
languages, so accessibility anchors and round-count invariants are
language-independent.

The ja transcript is **Word Wolf**, not the prisoners fixture: its statement →
two votes → tally → verdict fills the 6.9″ frame, where prisoners leaves the
lower ~40% blank. Its vote turns carry `reason` rather than `inner_thought`, and
`ScenarioConventions.thoughtField(for: .vote)` maps `reason` to the ▸ THINKING
section — so the shot-01 inner-voice caption holds for both locales, by
different fields.

### Why not `scripts/ui-tour.sh`

`ui-tour.sh` is the **design-review** tour, reused conceptually but not directly:
it has no pinned 6.9″ device (`sim-dest.sh` picks a 6.3″ iPhone 17 Pro), no
locale switching ("single configuration only for now" per its README), and no
scoreboard/observation capture points. `store-shots.sh` is the ASC-specific
sibling; both share the `xcresulttool export attachments` + `jq` extraction
shape.

## Shots (5 per locale × 2 locales = 10 PNGs)

| # | Screen | Reached via | EN caption | JA caption |
|---|---|---|---|---|
| 01 | Observation transcript (speech + inner-voice bubbles) | Past Results → seeded run's timeline (`resultDetail.timeline`) | Every word, and the thought behind it | 発言と、その裏にある心の声まで |
| 02 | Home — scenario list | launch root (`home.scenarioListCell.*`) | A pasture of scenarios to run | 実行できるシナリオが並ぶ牧場 |
| 03 | Visual scenario editor | Home → new scenario (`editor.titleField`) | Write your own world, no code needed | コード不要で、自分の世界を書く |
| 04 | Scoreboard / vote result | `--ui-test-open-scoreboard` (`scoreboard.list`) | Votes, scores, and the reveal | 投票、スコア、そして結末 |
| 05 | Past Results list | History tab (`results.list`) | Every run, saved to revisit | すべての実行を、あとから見返す |

> **Caption honesty note (critic Axis 8, App Review 2.3).** Shot 01 is the
> **Past-Results transcript replay**, not a live run (see the design decision
> below). It renders the *same* `AgentOutputRow` speech + inner-voice bubbles the
> live sim uses, so the screenshot is faithful — but the caption must not claim
> "live / real-time" over a replay screen. The softened wording above ("Every
> word, and the thought behind it") is replay-honest. `listing-{en,ja}.md`
> shot-1 caption + Screen column were updated to match this wording (#985).

Captions are also mirrored in `listing-en.md` / `listing-ja.md`; this table is
the single source. Overlay text is added in an image editor — ASC accepts raw
device screenshots, so overlays are optional polish.

## Design decision — transcript replay instead of live `SimulationView`

The hero "observation" shot is captured from the **Past-Results replay**, not a
live running `SimulationView`. Reason: under `--ui-test`,
`MockLLMService(responses: [])` throws on any generate call, so a live run
cannot be driven to a populated state deterministically; holding it mid-run only
yields empty bubbles. The replay screen shows the identical bubble components
with real seeded content (`StubResultSeeder`, which seeds `inner_thought` so the
▸ THINKING section renders), so it is the faithful, reproducible choice. A live
`SimulationView` capture would need canned per-turn `MockLLMService` responses
matched to a scenario's phases — brittle and out of scope for 1.0.

## Harness additions this pipeline relies on (all DEBUG-only)

- `StubResultSeeder` seeds a **thought field** on the fixture turns → the
  transcript renders speech **and** inner-voice bubbles. Which field is the
  thought depends on the phase (`ScenarioConventions.thoughtField(for:)`):
  `inner_thought` for `speak_all` / `speak_each` / `choose` / `whisper` (the en
  Alice/Bob fixture), `reason` for `vote` (the ja Word Wolf fixture). Do **not**
  add `inner_thought` to the marketing fixtures to "fix" this — they are
  verbatim transcripts of real runs, and inventing a field would be fabrication
  (see the same note in `StubResultSeeder.makePrisonersFixture`).
- `--ui-test-open-scoreboard` (in `PasturaApp.swift`, entirely `#if DEBUG`)
  presents `ScoreboardSheet` with fixed sample data so the scoreboard —
  otherwise reachable only from a completed live run — is capturable.
- `RootTabView` tabs carry `rootTab.*` accessibility identifiers so tab
  navigation is locale-independent (release-safe; benefits VoiceOver too).

## Status-bar chrome (optional polish)

For a clean 9:41 / full-battery status bar, override before capture (not wired
into the script — the raw simulator status bar is acceptable for ASC):

```bash
xcrun simctl status_bar "iPhone 17 Pro Max" override \
  --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

## Output location

- `docs/store/screenshots/{en,ja}/NN-screen.png` — **gitignored**, never committed.
- `.gitignore` entry `docs/store/screenshots/` is in place.

## Sources

- [App Store Connect — Screenshot specifications (Apple Developer)](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Store Screenshot Dimensions 2026 (Screenhance)](https://screenhance.com/blog/app-store-screenshot-dimensions-2026)
