---
paths:
  - "Pastura/PasturaUITests/**"
---

# XCUITest Traps

XCUITest-only footguns; SwiftUI traps are in `swiftui-traps.md`, test strategy in `view-testing.md`.

## structural `Tab`'s a11y overlay is a per-launch coin toss

With the iOS 18+ structural API, the identifier and label on the `Image` inside the `label:` closure are absent from the XCUITest tree **on some launches** — the raw SF Symbol name shows instead. It is decided when the a11y bridge is built, so waiting cannot outlast it and another identifier in `RootTabView.tabIcon` fixes nothing. The tab **button** keeps its localized title, so `app.tabBars.buttons["<label>"]` queries are unaffected. **Apply**: switch tabs via `ScreenshotSupport.tapTab`, whose **single** predicate ORs identifier and localized label; sequential waits burn the identifier's whole timeout first.

## An identifier on a container publishes no element — it propagates to the leaves

The identifier lands on the elements *below* the container, so `app.otherElements["X"]` finds nothing while the subtree is fully drawn — which reads as a render failure. **Apply**: match type-agnostically, `app.descendants(matching: .any).matching(identifier: "X").firstMatch`. Do not reach for `.accessibilityElement(children:)`; that changes the VoiceOver reading to serve the test, and on a list collapses every row into one stop.

**Which leaves receive it is not guessable, so measure.** A row carrying `.combine` surfaces as one `StaticText` labelled with the joined fragments, the same row without it as several — a *label* assertion written against one shape silently keeps passing under the other, so pin the joined label when rows combine.

To measure, fail a query on purpose (the hierarchy snapshot is captured on a **failing element query**, not on `XCTFail`), then `xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>` and read the "App UI hierarchy" `.txt`.
