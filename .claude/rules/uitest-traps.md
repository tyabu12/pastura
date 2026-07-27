---
paths:
  - "Pastura/PasturaUITests/**"
---

# XCUITest Traps

XCUITest-only footguns. App-source SwiftUI traps live in `swiftui-traps.md`;
the View-test *strategy* (what to unit-test vs. UI-test) is `view-testing.md`.

## structural `Tab`'s a11y overlay is a per-launch coin toss

With the iOS 18+ structural API (`TabView { Tab(...) { } label: { ... } }`),
**both** the `.accessibilityIdentifier` and the `.accessibilityLabel` applied
to the `Image` inside the `label:` closure are missing from the XCUITest tree
**on some launches** — the `Image` exposes its raw SF Symbol name instead. It
is decided once when the a11y bridge is built, so **waiting cannot outlast
it**: widening the bound (10s, 20s) does not help, and the session never
recovers. `scripts/store-shots.sh` failed 2 of 3 runs on this.

**The boundary matters — do not sweep working code.** The tab **button**
keeps its localized title, so `app.tabBars.buttons["<localized label>"]`
queries are unaffected (11 such call sites across `NavigationRegressionTests`,
`DeepLinkTabRoutingUITests`, `ScreenshotTourTests`, `SimulationFocusModeTests`
are fine as-is). Only queries keyed on the `label:`-closure identifier are
exposed.

**Apply**: switch tabs through `ScreenshotSupport.tapTab`, which waits on a
**single** predicate OR-ing identifier and localized label — not sequential
waits, or a broken launch burns the identifier's whole timeout first. Its doc
comment carries the AX-tree evidence and the label-fallback contract. Adding
another identifier in `RootTabView.tabIcon` does not fix it (#1271).
