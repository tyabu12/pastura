---
paths:
  - "Pastura/Pastura/**/*.swift"
---

# SwiftUI / Swift 6 Traps

Aggregation point for SwiftUI footguns, Swift 6 isolation quirks, and build-graph/xcodeproj traps that surface during Pastura app development. Loaded only when editing Swift files in the app target. Cross-references to `navigation.md` (always-loaded) for AppRouter / `PasturaBackButton` mechanics — this file is the trap catalog, that one is the navigation pattern.

## Toolbar-hide API matrix (iOS 17 → 26)

| API | Bar removed | Chevron preserved | Swipe-back preserved |
|---|---|---|---|
| `.toolbar(.hidden, for: .navigationBar)` | Yes | No | **No — FB13484530 on iOS 17+** |
| `.toolbarVisibility(.hidden, for: .navigationBar)` (iOS 18+) | Yes | No | **No — same bug surface** |
| `.navigationBarBackButtonHidden(true)` | No (bar stays) | No (button hidden) | iOS 17–18: yes / **iOS 26: NO** |
| `.toolbarBackground(.hidden, for: .navigationBar)` | No (bar stays) | Yes | Yes |

Root cause for the iOS 26 regression on `.navigationBarBackButtonHidden(true)`: SwiftUI sees "no back affordance" and disables `interactivePopGestureRecognizer` system-wide. Contradicts older web articles claiming only `.toolbar(.hidden)` does this.

**Apply**:

- "Reclaim nav bar space" → **fill-the-bar**: `.toolbarBackground(.hidden, for: .navigationBar)` + `ToolbarItem(.principal)` (Apple HIG; Messages / Slack / Telegram all do this). Do NOT use `.toolbar(.hidden)` even with UIKit-Introspect escape hatches.
- "Replace system back chevron" → `PasturaBackButton` (see `.claude/rules/navigation.md` § Custom back button). The reference impl `Pastura/Pastura/Views/Components/PasturaBackButton.swift` mounts a UIKit-bridge probe that reinstalls the gesture recognizer.
- **Simulator-only QA is not load-bearing for these.** Real-device verification required on iOS 26 visual changes specifically.

Architectural rationale: [ADR-008 §Amendment 2026-05-10](../../docs/decisions/ADR-008.md).

## TabView tab-bar SF Symbol auto-fill (iOS 15+)

A native `TabView` tab bar auto-applies the `.fill` SF Symbol variant to
**every** tab icon (iOS 15+). If you drive the active/inactive
outline↔fill distinction yourself (e.g. `house` ↔ `house.fill`), the
auto-fill overrides it — every tab renders filled in both states and the
distinction is erased.

**Apply**: add `.environment(\.symbolVariants, .none)` to each tab
`Image` to disable the auto-variant, then let your own `isActive`-driven
symbol name carry the fill toggle. The modifier is LOAD-BEARING —
removing it silently re-fills every tab.

Reference impl + full rationale (including why `magnifyingglass`, which
has no `.fill` variant, was the only tab where the symptom was
diagnosable): the LOAD-BEARING comment in
`Pastura/Pastura/App/RootTabView.swift` (`symbolName(for:isActive:)`).

## NavigationStack in-place top-route replace (`AppRouter.replaceTop`)

Replacing the **top route in place** in a `NavigationStack` path
(`AppRouter.replaceTop`, used by the ScenarioDetail cross-language toggle)
is NOT a push, and trips two **device-only** traps (neither reproduces in
simulator reasoning). Why replace at all: ja/en variants are distinct
`scenarioId`s = distinct `Route`s, so a plain push grows the stack
unboundedly on repeated toggling and `pushIfOnTop` can't dedupe them —
`replaceTop` keeps stack depth constant.

1. **Leaf identity is reused by stack position, not by `Route` value.** A
   load-once view (`.task { guard viewModel == nil }`) keeps showing the
   PRIOR data after a swap — `.task` never re-fires. **Fix:** key the load
   on the changing field — `.task(id: scenarioId)` (drop the guard; build
   the new VM fully before assigning to avoid a ProgressView flash).
2. **Scroll offset is restored by nav position.** Even `.id(scenarioId)` on
   the leaf (full subtree rebuild) does NOT reset it. **Fix:**
   `ScrollPosition.scrollTo(edge: .top)` (iOS 18+, bound via
   `.scrollPosition(_:)`) — lands at true offset 0 so a `.large` nav title
   re-expands. `ScrollViewReader.scrollTo(_:anchor:.top)` is NOT equivalent:
   it aligns the first item one title-height below 0 and collapses the large
   title to inline (#830).

Reference impls: `AppRouter.replaceTop`, `ScenarioDetailView.scenarioContent`.
`replaceTop` is a navigation-path mutator alongside `push`/`pop` — see
`navigation.md` § AppRouter scope.

## Production-side-effecting service: inject at View boundary

When introducing a **production-only side-effecting service** (LLM-output detector, telemetry analyzer, content-rewriting filter, on-the-fly classifier, A/B-flag injector), inject it at the **View boundary**, NOT as a default value on the VM's `init()` signature.

### Why

VM `init()` default arguments run **in tests too**. Fixture-driven tests that pre-load `MockLLMService(responses: [...])` queues construct the VM via the no-arg overload (`SimulationViewModel(simulationRepository: …, …)`). If the VM's `init()` defaults to `SimulationRunner(detector: NLLanguageDetector())`, the detector fires on every output → consumes the mock queue unexpectedly → cascading "Mock exhausted" errors.

### Apply

- VM `init()` default for production-only services: **leave nil-equivalent** (`SimulationRunner()`, `ContentFilter.passthrough`, etc.). Tests get back-compat behavior.
- Add production injection at the **consuming View** in App layer (e.g., `SimulationView` constructs `SimulationViewModel(runner: SimulationRunner(detector: …))`).
- Add a one-line comment at the View injection site noting *why* the default isn't on the VM — saves the next refactor from "helpfully" moving it back.

### Detection rule

If adding `Foo` to `VMInit` would cause `VMInit(repo: …)` (no `foo:` arg) to behave differently in tests, push the default down to the View. Pure-data services (config readers, immutable repositories) don't have this problem.

## SwiftUI drag & drop inside List / Form

`.dropDestination(for:action:isTargeted:)`'s **`isTargeted` closure never
fires** inside `List` / `Form` rows on iOS 17–26 (FB12980427 / FB21980712,
unfixed by Apple as of 2026-04). The drop action fires on release, but
hover feedback is silent. macOS works correctly. `DropDelegate.dropEntered`
/ `dropExited` are reported to work in `List` but empirically also failed
in `Form` rows on iOS 26 simulator.

Apple's `.onMove(perform:)` is **deliberately single-`ForEach` only** —
moving items between two `ForEach` instances is not supported by design
([Apple Dev Forums thread/674393](https://developer.apple.com/forums/thread/674393)).
HIG has no cross-collection drag pattern; Apple's documented alternative
is the **context-menu "Move to X" action**.

### Apply

Answer first, before designing:

- Same-collection reorder? → `.onMove` works.
- Cross-collection move? → **prefer context menu**. Drag will fight the platform.
- Hover indicator on `List` / `Form`? → cannot be delivered natively on current
  iOS. Switch to `ScrollView` + `LazyVStack` (loses List chrome) or drop the
  indicator requirement.

For the workflow lesson "research platform support BEFORE plan / critic,
not after a full PR cycle" see #144.

### Sources

- [Apple Dev Forums thread/674393](https://developer.apple.com/forums/thread/674393) (cross-section drag)
- [Apple Dev Forums thread/730367](https://developer.apple.com/forums/thread/730367) (dropDestination in List)
- [HIG — Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop)

## `.accessibilityIdentifier` ordering around `.safeAreaInset`

`.accessibilityIdentifier("X")` applied to a container **after**
`.safeAreaInset(edge:)` scopes "X" into the inset's child subtree,
**overriding** a child button's own `.accessibilityIdentifier("Y")`. In
XCUITest the button then surfaces with identifier "X", so `app.buttons["Y"]`
never resolves — a silent break (the element exists, just under the wrong id).
Scoped to the **container the inset is attached to** (outer position), not a
blanket "id always leaks."

**Apply**: put the container's `.accessibilityIdentifier` **before**
`.safeAreaInset`, so the inset content stays out of that id's scope.

```swift
ScrollView { … }
  .accessibilityIdentifier("myScreen.list")   // BEFORE — scopes scroll content only
  .safeAreaInset(edge: .bottom) { footerButton }  // inset keeps its own button id
```

The motivating instance — `ScenarioDetailView`'s bottom Run CTA under
`scenarioDetail.list` — was moved into the toolbar (#851), so no live
in-repo case of this exact bottom-inset-plus-button-id shape remains; the
trap still applies to any future bottom-`safeAreaInset` that hosts an
id'd control. The other live bottom-`.safeAreaInset` user
(`ModelDownloadHostView+ChatStream.swift`, `promoCardInset`) doesn't hit
it because its inset content carries no competing button id.

**Diagnose** which id an element actually carries — instead of guessing —
by exporting the a11y snapshot from the failing `.xcresult`:
`xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>`,
then read the "App UI hierarchy" `.txt`.

## Duplicate base filename → `.stringsdata` collision (build trap, not SwiftUI)

Two Swift files with the same **base name** in one target fail the build with
`error: Multiple commands produce '…/<Name>.stringsdata'` (each Swift file emits
one `<BaseName>.stringsdata`). Easy to hit under Pastura's
`PBXFileSystemSynchronizedRootGroup` — sync folder groups auto-include every new
file under `Pastura/`, so a duplicate base name **anywhere** in the tree (even
cross-layer) collides.

**Apply**: before adding a file, `find Pastura/Pastura -name '<Name>*.swift'`;
if taken, pick a distinct name (rename the type too if it also clashes). Case
study: #759 renamed a new `ScenarioSummary.swift` (Views) that collided with the
Data-layer `ScenarioSummary` → `ScenarioSummaryStrip`.

## iOS 26 `.confirmationDialog` renders as a mis-anchored popover

On iOS 26 a SwiftUI `.confirmationDialog` **anchored to a specific control** — a
`⋯`-`Menu` item or a row button in a list/menu — renders on iPhone as a **popover
whose arrow anchors to the body centre**, pointing at empty space, not the control
that opened it. `.confirmationDialog` exposes no source-anchor API, so the anchor
cannot be fixed. **Carve-out**: scene-level `isPresented`-driven *choice* dialogs
(cellular-consent `CellularConsentDialogModifier` in `PasturaApp.swift`,
`ModelDownloadHostView.swift`) are NOT control-anchored and render acceptably —
keep those as `.confirmationDialog`.

**Use `.alert` for the control-anchored confirmations** — a centred modal, no arrow,
presents correctly regardless of trigger. Two caveats:
- `.alert` does NOT auto-add a Cancel button (confirmationDialog does) — add
  `Button(role: .cancel) {}` explicitly.
- `.alert` supports `presenting:` for item-scoped dialogs, same as confirmationDialog.

In-code rationale lives at the delete-confirmation callsites (`ResultDetailView+Delete.swift`,
`HomeView.swift`, `ScenarioDetailView.swift`, `SettingsView+PastResults.swift`).

## iOS 26 Liquid Glass toolbar capsule — `.buttonStyle(.plain)` does NOT remove it

On iOS 26 every `ToolbarItem` is wrapped in a translucent Liquid Glass capsule by the
**toolbar itself**, independently of the inner `Button`'s style. `.buttonStyle(.plain)`
only changes how content renders *inside* the capsule — it does **not** remove the
capsule. The documented opt-out is `sharedBackgroundVisibility(.hidden)` on
`ToolbarContent` (iOS 26+).

Pastura wraps it for its sub-iOS-26 deployment target (iOS 18, ADR-019) as
`ToolbarContent.hidingPasturaSharedBackground()` (`PasturaBackButton.swift`) — apply to
every `ToolbarItem` that wraps a custom Pastura control. Caveats:
- **Real-device verification required**: the iOS 26 simulator suppresses the capsule even
  without the opt-out, so the simulator visual is misleading.
- `UIDesignRequiresCompatibility = YES` (Info.plist) is the global escape hatch; Pastura
  uses per-item opt-out instead, so that key is NOT set.

Canonical source for this fact: `docs/design/design-system.md` § 5.8.1 (the
`PasturaBackButton` spec) — `navigation.md` and the `PasturaBackButton.swift`
doc-comment also reference the capsule opt-out; keep this entry pointing there so the
loci don't drift.

## Swift 6 makes accessibility env keypaths read-only

Pre-Swift-6, `.environment(\.accessibilityReduceMotion, true)` inside a `#Preview`
overrode the value for visual testing. Under the project's Swift 6 mode, the system
accessibility env keypath resolves as `any KeyPath<EnvironmentValues, Bool> & Sendable`,
NOT `WritableKeyPath`, so `.environment(_:_:)` no longer accepts it (compile error:
`cannot convert ... to expected argument type 'WritableKeyPath<...>'`). Affects
`accessibilityReduceMotion`,
`accessibilityReduceTransparency`, and the other system-set (app-read) accessibility env
values.

**Pattern**: extract animation timing into a `nonisolated enum` of pure functions taking
`reduceMotion: Bool` (see `ModelSelectionAnimations`); the View reads
`@Environment(\.accessibilityReduceMotion)` and forwards per call site; unit-test the pure
helper across the phase × reduceMotion matrix. Do NOT write the Preview override; cover
visual parity with manual QA (Settings → Accessibility → Reduce Motion → relaunch).

## Custom `Color` tokens don't work with `.foregroundStyle` dot-syntax

`.foregroundStyle(.muted)` (and any `PasturaPalette`-derived token: `.ink`, `.inkSecondary`,
`.moss`, `.mossDark`, …) does **not** compile — the leading-dot in `foregroundStyle(_:)`
resolves against `HierarchicalShapeStyle`/`ShapeStyle`, not `Color`. Our tokens live only on
`Color` (`DesignTokens+SwiftUI.swift`), so write the type explicitly:
`.foregroundStyle(Color.muted)`.

System hierarchy styles (`.secondary`, `.tertiary`, `.quaternary`, `.clear`) *do* work with
dot-syntax because they're `ShapeStyle` conformances — which is why pre-token code compiled.
When token-izing `.foregroundStyle(.secondary)`, always switch to `Color.tokenName`.

## `.sheet(item:)` — pass `Optional<Model>`, never `Int: Identifiable`

For `.sheet(item: $binding)`, pass the **model itself** as `Optional<Model>`. Never wrap an
array index in a project-wide `extension Int: Identifiable` — it applies to every `Int` in
the project, conflicts with future Swift evolution, and silently affects any code passing
`Int` where `Identifiable` is expected. Capturing an array index in the sheet closure also
risks out-of-bounds if the array mutates between trigger and body evaluation; do a
`firstIndex(where: { $0.id == item.id })` lookup inside the closure instead.

## Never instantiate a ViewModel in a factory func / computed property

A ViewModel created inside a View function or computed property (`let vm = MyViewModel()`
then `return EditorView(viewModel: vm)`) gets a **fresh instance on every `body`
re-evaluation**, silently wiping user state — because `@Bindable`/`@Observable` references
observe but do not own. Retain it with `@State` in a host view that creates the VM once
(`.task { guard viewModel == nil ... }`), rendering a `ProgressView` until it exists.
