# Design-review motion captures

Filmstrips and frame sequences of the app's animations, for design review
by humans and agents — the *time axis* a single screenshot can't show.
**The captures are gitignored** — regenerate on demand:

```bash
scripts/motion-capture.sh          # all variants
scripts/motion-capture.sh cold     # a single variant
```

The script builds the app, records the simulator with
`xcrun simctl io recordVideo` while a forced launch animation plays, then
expands each recording with ffmpeg into `<variant>/filmstrip.png` (frames
tiled left → right) plus `<variant>/frames/frame_NNN.png`. Requires
`ffmpeg` (`brew install ffmpeg`). Takes a few minutes including the build.
Local-run only — **not** a CI gate (mirrors `scripts/ui-tour.sh`).

## Truth vs. design intent

This directory holds **truth**: what the animation actually does on the
simulator, frame by frame. The **design intent** for the same motion lives
in [`../ds/motion.html`](../ds/motion.html) — the Claude Design mirror of
the duration / easing table in [`../design-system.md`](../design-system.md)
§6 that the animation is built against. Review divergence between the two
here; never let the HTML mirror stand in for the real frames. Same split as
[`../screenshots/`](../screenshots/README.md) (static screens) vs. the
design system.

## Variants (launch animation)

| Variant | Launch args | What plays |
|---------|-------------|-----------|
| `cold` | `--capture-launch` | "Pastoral Drift" full cold-launch splash (`ColdSplashView`) |
| `warm` | `--capture-launch-warm` | abbreviated "Breath" warm-launch splash (`WarmSplashView`) |
| `reduce-motion` | `--capture-launch` + sim Reduce Motion on | cold splash's opacity-only fallback |

Each recording opens on the springboard → launch transition, then the
splash, then Home (seeded via `--ui-test`). That whole sequence is genuine
app behaviour — including the static `UILaunchScreen` → SwiftUI
`ColdSplashView` handoff — so the leading frames showing the home screen /
launch transition are expected, not capture noise. Where each screen sits
in the navigation graph: [`../navigation-map.md`](../navigation-map.md).

Frame rate and per-frame width are tunable via env vars: `MOTION_FPS`
(default 12), `MOTION_THUMB_W` (default 160 px). The filmstrip width is
`frame_count × MOTION_THUMB_W`, so a high `MOTION_FPS` makes it very wide —
use the `frames/` sequence for fine inspection in that case. The internal
launch-cache warm-up and settle delays are tuned for a typical Apple-silicon
host; bump them if captures clip the splash on a slower machine.

## How the splash is forced

Under `--ui-test` the splash is normally suppressed (it would slow every
test). The DEBUG-only `--capture-launch` / `--capture-launch-warm` launch
args (see `Pastura/Pastura/PasturaApp.swift`) override that so the splash
plays over the `--ui-test` Home fixtures. Reduce Motion is driven by the
simulator accessibility setting because
`@Environment(\.accessibilityReduceMotion)` is read-only in Swift 6 and
can't be injected from code; the script saves and restores its prior value.

## Deferred (not yet captured)

- **Bubble entrance / vote bubbles** (`../design-system.md` §6 — バブル登場
  700 ms) — needs a running simulation, but `MockLLMService` launches with
  an empty response queue under `--ui-test`, so a live turn errors on first
  inference. Same reachability blocker as the mid-run Simulation screenshot
  in [`../screenshots/README.md`](../screenshots/README.md).
- **DL progress dots** (`../design-system.md` §6 — DL ドット点灯 600 ms) —
  `--ui-test` bypasses the model-download flow entirely, so the dots never
  animate. Same blocker as the ModelSelection / ModelDownload screenshots,
  deferred there too.

Capturing either needs the same dedicated launch-argument seeding the
screenshot tour defers — a canned-response queue for the simulation, and a
download-flow path that isn't short-circuited by `--ui-test`.

## Don't run concurrently

`motion-capture.sh` mutates the simulator's Reduce Motion setting and holds
a video recorder, and the `sim-dest.sh` gate only sees `xcodebuild test` —
not `simctl io`. Don't run it at the same time as `scripts/ui-tour.sh` or
`xcodebuild test` against the same simulator.
</content>
