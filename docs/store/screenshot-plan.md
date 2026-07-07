# App Store screenshot plan

> Capture plan for the 1.0 submission. PNGs are **not committed** — they render
> to a gitignored local dir (`docs/store/screenshots/`, added to `.gitignore`).
> This file is the committed artifact; the capture is a local/manual step.

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
| iPhone 6.9″ | **1320 × 2868** px portrait (or 1290 × 2796) | iPhone 16 Pro Max / 17 Pro Max sim → 1320×2868; iPhone 15 Pro Max → 1290×2796 |
| iPad 13″ | — not required (iPhone-only) | — |

Format rules: **PNG or JPEG, RGB, no alpha channel, exact pixel dimensions
(no off-by-one tolerance), 1–10 per size.** Use **iPhone 16 Pro Max** simulator
(→ 1320×2868) as the canonical capture device.

## Shots (5 per locale × 2 locales = 10 PNGs)

| # | Screen | What it shows | EN caption | JA caption |
|---|---|---|---|---|
| 1 | Simulation running | speech bubbles, inner-voice reveal, live typing | Watch agents think in real time | エージェントの思考を、リアルタイムで |
| 2 | Home — scenario list | the scenario "pasture" / bottom-tab home | A pasture of scenarios to run | 実行できるシナリオが並ぶ牧場 |
| 3 | Visual scenario editor | form fields: personas, phases, win conditions | Write your own world, no code needed | コード不要で、自分の世界を書く |
| 4 | Vote / score results | vote tally + scoreboard + reveal | Votes, scores, and the reveal | 投票、スコア、そして結末 |
| 5 | Past Results | saved run list / a re-opened transcript | Every run, saved to revisit | すべての実行を、あとから見返す |

Captions are also recorded in `listing-en.md` / `listing-ja.md` (single source is
this table; the listing files mirror it). Overlay text is added in an image
editor — ASC accepts raw device screenshots, so overlays are optional polish.

## Tooling — why `ui-tour.sh` is not reusable as-is

`scripts/ui-tour.sh` is a **design-review** tool, not an ASC pipeline. Three gaps:

1. **No pinned 6.9″ device** — `sim-dest.sh` picks the first available from an
   iPhone priority list (17 Pro / 17 / Air / 17e / 16 / 16e / 15 Pro / 15). Not
   guaranteed to be a Max-class 6.9″ device, so output pixel size isn't
   guaranteed to be 1320×2868 / 1290×2796.
2. **No locale switching** — its README states "single configuration only for
   now" (ja/dark/Dynamic Type variants explicitly deferred). It can't emit the
   ja set B-1a requires.
3. **No iPad target** — moot now (iPhone-only), but noted for completeness.

Its deterministic `--ui-test` launch mode (in-memory DB, `MockLLMService`,
`StubGalleryService`, seeded content) **is** worth reusing — it gives clean,
reproducible screens without a real 3 GB model. The gap is device-pinning +
locale, not the content harness.

## Capture procedure (manual, 1.0)

For 10 shots, manual capture is cheaper than extending the tour. Commands:

```bash
# 0. Build+install the app to the sim (deterministic UI-test content, clean chrome).
#    Easiest: run the ScreenshotTour UI test on the pinned device, OR launch the
#    app manually with the --ui-test flag from Xcode on "iPhone 16 Pro Max".

DEVICE="iPhone 16 Pro Max"        # renders 1320 x 2868
xcrun simctl boot "$DEVICE"

# 1. Clean status bar: 9:41, full battery, full bars (App Store convention).
xcrun simctl status_bar "$DEVICE" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

# 2a. Launch in ENGLISH, navigate to each screen, capture:
xcrun simctl launch "$DEVICE" app.pastura.Pastura -AppleLanguages "(en)" -AppleLocale en_US
mkdir -p docs/store/screenshots/en
xcrun simctl io "$DEVICE" screenshot docs/store/screenshots/en/01-simulation.png
#   ...repeat navigate+screenshot for 02..05

# 2b. Terminate, relaunch in JAPANESE, repeat:
xcrun simctl terminate "$DEVICE" app.pastura.Pastura
xcrun simctl launch "$DEVICE" app.pastura.Pastura -AppleLanguages "(ja)" -AppleLocale ja_JP
mkdir -p docs/store/screenshots/ja
xcrun simctl io "$DEVICE" screenshot docs/store/screenshots/ja/01-simulation.png
#   ...repeat for 02..05
```

Verify every PNG is exactly 1320×2868 (or 1290×2796) with no alpha before upload:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha docs/store/screenshots/**/*.png
```

## Durable path (future, optional)

Extending `ui-tour.sh` with a `--locale` flag + a pinned 6.9″ `--device` would
make the store set reproducible (one command per locale). Worth a follow-up issue
if store screenshots need regular refresh across releases; skipped for 1.0.

## Output location

- `docs/store/screenshots/{en,ja}/NN-<screen>.png` — **gitignored**, never committed.
- `.gitignore` entry `docs/store/screenshots/` is added in this PR.

## Sources

- [App Store Connect — Screenshot specifications (Apple Developer)](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Store Screenshot Dimensions 2026 (Screenhance)](https://screenhance.com/blog/app-store-screenshot-dimensions-2026)
