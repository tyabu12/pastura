---
paths:
  - "Pastura/Pastura/**/*.swift"
---

# SwiftUI / Swift 6 Traps

Aggregation point for SwiftUI footguns, Swift 6 isolation quirks, and build-graph/xcodeproj traps that surface during Pastura app development. Loaded when a Swift file in the app target is read (an edit reads it first). Cross-references to `navigation.md` (path-scoped to the same Swift glob, so loaded alongside these edits) for AppRouter / `PasturaBackButton` mechanics — this file is the trap catalog, that one is the navigation pattern.

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

The a11y modifiers on that same `tabIcon` `Image` are separately unreliable
— structural `Tab` drops them from the XCUITest tree on some launches, so
adding another identifier there fixes nothing. See `uitest-traps.md`
§ "structural `Tab`'s a11y overlay is a per-launch coin toss".

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
  .accessibilityIdentifier("scenarioDetail.list")   // BEFORE — scopes scroll content only
  .safeAreaInset(edge: .bottom) { actionBar }         // inset keeps its own button id
```

Reference + inline rationale: `ScenarioDetailView.swift` (`scenarioDetail.list`
just above its `.safeAreaInset` hosting `ScenarioDetailActionBar`, whose Run
button carries `scenarioDetail.runSimulationButton`).

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

## SwiftLint directive placement around a `///` doc comment (lint trap, not SwiftUI)

A `swiftlint:disable[:next] X` directive can't cleanly suppress a rule on a
declaration that also carries a `///` doc comment — **both** placements fail:

- **Between the doc comment and the declaration** (a `// swiftlint:disable:next X`
  line separating `/// …` from the `func`): detaches the doc comment, firing
  `orphaned_doc_comment`.
- **Inside the `///` block** (`/// swiftlint:disable:next X`): a **no-op** under
  `swiftlint --strict` — the comment-command parser recognizes `//`-form only, so
  the warning upgrades to an error unsuppressed. It looks load-bearing but is
  untested until the body later crosses the threshold.

**Apply** — don't relocate the directive; remove the need for it:

- `function_body_length` → **extract a helper** so each body stays under the
  threshold. Ref: `BundledDemoReplaySource.loadOne` → `buildSourceOrSkip`.
- `identifier_name` (short domain identifiers like `ja` / `en`) → add a
  **`.swiftlint.yml` `identifier_name.excluded`** entry (ref: the `ja` / `en`
  exclusions consumed by `pickLanguage(_:ja:en:)`), or rename to 3+ chars.

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

## Adding a `Color` design token = 5 files; the 5th fails silently (workflow trap, not SwiftUI)

A new color token needs five edits — miss the **5th** (the CSS mirror) and *only* the standalone
`Design tokens drift guard` CI job reddens; build / unit / lint stay green, so it's invisible
locally (first hit PR #953):

1. `DesignTokens+ExtendedPalette.swift` — raw `PasturaColorValue(hex:)` token
2. `DesignTokens+SwiftUI.swift` — SwiftUI `Color` alias
3. `PasturaTests/Views/DesignTokensTests.swift` — assert it
4. `docs/design/design-system.md` § "2. カラートークン" — document it
5. `docs/design/ds/tokens.css` — CSS mirror; the token's CSS form must appear here

`scripts/check_design_tokens_css.py` is the source of truth for the mirror check (hex vs `rgba`
form, `EXCEPTIONS` exemptions).

**Adding a dark *counterpart* to an existing token is a different, 6th-file shape** — the five
steps above assume a brand-new value. A dark pair adds: the `night*` raw token (step 1), its
`Color` alias, a `PasturaDynamicColor` entry in `DesignTokens+DynamicColor.swift`'s
`PasturaDynamicPalette` (including its `all` registry — its count assertion guards
that list's documented size, not completeness: an unregistered pair still passes), the
light alias repointed from `PasturaPalette.x.color` to `PasturaDynamicPalette.x.color`, plus
steps 3–5. Note the CSS gate keys off `PasturaColorValue(hex:)` literals, so the pairing file
itself is inert to it — only the new `night*` hex needs a `tokens.css` row. See ADR-028.

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

## iOS 26 AttributeGraph crash — ForEach + glyph in a plain-ScrollView card

Adding an **unconditional** subview (an `Image`/glyph, a `.background(_, in: Capsule())`
badge like `PhaseTypeLabel`) to a `ForEach` that renders inside a plain **`ScrollView` →
eager `VStack`** (custom card, NOT `List`/`Form`/`LazyVStack`) under a `NavigationStack`
with a `.large` title + `.safeAreaInset` + a `.background(...ignoresSafeArea())` can crash
on iOS 26 with `EXC_BAD_ACCESS` the instant the screen appears — a pure-SwiftUI fault stack
(`ForEachChild.updateValue → PairPreferenceCombiner → ContainerBackgroundKeys.NavigationKey
→ AttributeGraph`), no app frame. A row with a *conditional* extra subview survives;
the same badge renders fine in a `LazyVStack` (Sim conversation) or `List`/`Form` (editor).

**Two load-bearing lessons — the crash itself is now secondary:**

1. **Render crashes are invisible to `xcodebuild build` + the full unit suite** (both stay
   green). Only a UI test that navigates in and renders catches them. For a View-tree change
   on a screen the UI tests exercise, run at least one navigating UI test (cheapest that
   lands on ScenarioDetail: `PasturaUITests/BackGestureTests/testBackGestureFromScenarioDetailReturnsToHome`).
   Diagnose from `~/Library/Logs/DiagnosticReports/Pastura-*.ips` frames, not the XCUITest
   assertion message.
2. **These AttributeGraph crashes can be OS-build-specific and self-resolve.** This one
   (`ScenarioDetailView.phasesSection`, #901) was real on iOS 26.5 on 2026-07-03 but no
   longer reproduced on iOS 26.5 (23F77) — sim OR real device — on 2026-07-04, so the glyph
   shipped with **no** code workaround. Before investing in a workaround, confirm the repro
   on the **exact OS build AND a real device** (the sim misleads both ways). If one does
   resurface, the candidate workarounds, in order: extract the row into a concrete `View`
   struct → `.compositingGroup()` on the row → `LazyVStack` → drop the enumerated-`\.offset`
   `ForEach` shape → bisect the container `.background(...ignoresSafeArea())` half the fault
   stack names → `.geometryGroup()`. See #901 for the full diagnostic write-up.

## Re-projection resets `@State` — put run-scoped display state on the VM

Re-projecting an **already-running** `@Observable` VM into a **fresh** `View`
instance (ADR-017 Phase B "keep running": `SimulationSession.adoptIfMatching`
re-mounts `SimulationView` onto the parked run, source unchanged) resets
**every** `@State` in that view and its rows. Adopt rescues the *VM*; the fresh
view instance is what clears the `@State`. Any "already shown / revealed /
animated" latch that lives only in per-View or per-row `@State` therefore
**replays** on return — the user re-watches content they already saw.

**Apply**: run-scoped display state that must survive a return-to-run belongs on
the **surviving VM**, not View/row `@State`; read it back through a VM property /
method so re-projection restores it. Distinct from the fresh-VM `.resume` path
(guarded separately via `isResumeEntry` / `effectiveCharsPerSecond`) — the trap
is specific to re-projecting an already-running VM.

Reference: #934 — the premise card + latest conversation row re-typed from View
`introHasTyped` / row `visibleChars` `@State`; moved to
`SimulationViewModel.introRevealHasBegun` / `latestRowRevealCompleted` (see the
adopt early-return comment in `SimulationView`).

## `ImageRenderer` does not inherit the ambient environment

`ImageRenderer` rasterizes its content in a **default** environment — it does
NOT pick up the caller's ambient `@Environment` (notably `\.colorScheme`). No
diagnostic; the bug is appearance-only and surfaces just on a dark-mode device.

**The `Color.*` aliases now make this sharper, not milder.** Eight of them
(`screenBackground`/`bubbleBackground`/`whisperBubble`/`ink`/`inkSecondary`/
`muted`/`rule`/`moss`) resolve light↔dark against the ambient interface style
(ADR-028), so reading one inside `ImageRenderer` content means "whatever
appearance the renderer resolved" — and an explicitly light or dark export
becomes unexpressible. The other 77 aliases are still fixed (60 of them unpaired
light tokens; the rest `night*` / time-of-day / chart), so a
token-styled view otherwise rasterizes in one appearance regardless of device.

**Apply**: pass the appearance in **explicitly** — capture
`@Environment(\.colorScheme)` at the call site, and drive the view's palette
from that value (an explicit `colorScheme` parameter) reading
**`PasturaPalette.<token>.color`, never the `Color.*` alias** — the raw palette
values are fixed sRGB, which is exactly the property an export needs. Also set
`.environment(\.colorScheme, …)` on the rendered content for any system-colored
subviews (SF Symbols, asset images). Real-device dark-mode QA required — the
simulator misleads.

**What catches a regression here**: the token tests assert `PasturaPalette`
components *and* the aliases' own resolution, and `HighlightShareCardPaletteTests`
pins the reference consumer's two families to raw palette values — so an alias
creeping back into that palette reddens. ADR-009 rules out snapshots, so any
*new* fixed-appearance consumer needs its own equivalent pin or it is unguarded.
Reference consumer: `HighlightCardPalette`.

Reference: `HighlightCardImageRenderer.render` + `HighlightShareCard` (#1070).
