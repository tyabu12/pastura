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

## An identifier on a container publishes no element — it propagates to the leaves

`.accessibilityIdentifier("X")` on a SwiftUI container that is not itself an
accessibility element does **not** create one queryable element. The identifier
lands on the elements *below* it, so `app.otherElements["X"]` finds nothing
while the subtree is fully drawn — which reads as a render failure and sends you
looking for a crash that never happened.

**Apply**: match type-agnostically —
`app.descendants(matching: .any).matching(identifier: "X").firstMatch` — and do
not reach for `.accessibilityElement(children:)` to "fix" the query. That
changes the VoiceOver reading to serve the test, and on a list it collapses
every row into one stop.

**Which leaves receive it is not guessable, so measure.** It shifts with the
subtree's own a11y modifiers: a row carrying `.combine` surfaces as one
`StaticText` labelled with the joined fragments, while the same row without it
surfaces as several. A *label* assertion written against one shape silently
keeps passing under the other, so it is not a probe of anything you think it
is — pin the joined label when rows combine (#1394).

**The snapshot is only captured on a failing element query**, not on
`XCTFail`. To read the real tree, make a query fail on purpose, then
`xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`
and open the "App UI hierarchy" `.txt` (same export as `swiftui-traps.md`
§ ".accessibilityIdentifier ordering").
