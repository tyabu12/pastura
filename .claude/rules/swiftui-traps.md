---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
---

# SwiftUI / Swift 6 Traps

Aggregation point for SwiftUI footguns and Swift 6 isolation quirks that surface during Pastura UI development. Loaded when a file in the UI layers is read (an edit reads it first).

**Scope** — the globs above are **identical to `navigation.md`'s**, deliberately: every trap here is *entered from* a UI-layer file, and `PasturaApp.swift` is the only file outside `Views/` / `App/` that imports SwiftUI (`grep -rl "import SwiftUI" Pastura/Pastura --include='*.swift'`). Not every one is a *SwiftUI* trap: § "Adding a `Color` design token = 5 files; the 5th fails silently (workflow trap, not SwiftUI)" has later steps landing in a test file and `docs/design/**` — it stays here because its entry point is `DesignTokens+*.swift`. Traps with no UI entry point at all — filename collisions, SwiftLint directive placement — live in `build-traps.md`, whose globs are the union of the two traps' differing reach. `navigation.md` carries AppRouter / `PasturaBackButton` mechanics: this file is the trap catalog, that one is the navigation pattern.

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

Sources and the workflow lesson "research platform support BEFORE plan / critic,
not after a full PR cycle": #144.

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

A new color token needs five edits — miss the **5th** (the CSS mirror) and *at best only* the standalone
`Design tokens drift guard` CI job reddens; build / unit / lint stay green, so it's invisible
locally:

1. `DesignTokens+ExtendedPalette.swift` — raw `PasturaColorValue(hex:)` token
2. `DesignTokens+SwiftUI.swift` — SwiftUI `Color` alias
3. `PasturaTests/Views/DesignTokensTests.swift` — assert it
4. `docs/design/design-system.md` § "2. カラートークン" — document it
5. `docs/design/ds/tokens.css` — CSS mirror; the token's CSS form must appear here

`scripts/check_design_tokens_css.py` is the source of truth for the mirror check (hex vs `rgba`
form, `EXCEPTIONS` exemptions) — but it is a **substring match on the hex** over the raw file, so a
token whose value already appears under another name (`inkOnAccent` #FFFFFF vs `--bubble-bg`) has
**no automated detector for its step-5 row**: delete that row and the job still exits 0. Steps 1–3,
*when done*, still assert the token's value — but nothing enforces that they were. Verify by diff
(#1299).

**Adding a dark *counterpart* to an existing token is a different, 6th-file shape** — the five
steps above assume a brand-new value. A dark pair adds the `night*` raw token in
`DesignTokens+NightPalette.swift` (not step 1's file), its `Color` alias, a
`PasturaDynamicColor` entry in `DesignTokens+DynamicPalette.swift`'s `PasturaDynamicPalette`
including its `all` registry, and the light alias repointed from `PasturaPalette.x.color` to
`PasturaDynamicPalette.x.color` — plus steps 3–5. Two silent gaps here: the `all` registry's
count assertion guards that list's documented size, **not** completeness, so an unregistered
pair still passes; and the CSS gate keys off `PasturaColorValue(hex:)` literals, so **both**
pairing files (`+DynamicColor.swift`, the mechanism; `+DynamicPalette.swift`, the table) are
inert to it — only the new `night*` hex needs a `tokens.css` row. Keep every
`DesignTokens+*` filename inside `check_design_tokens_css.py`'s glob; renaming one out blinds
the gate silently (each file's own header says so). See ADR-028.

**Choosing the value: a token-pair ratio is not a prediction about a *presented* surface.** For a
sheet / overlay fill, the comparand is the **composited** backdrop — the presentation dims what is
behind and not the surface itself, which can flip the sign, so a pair designed to sit *below* its
ground can render *above* its own backdrop. Judge such a value against a device screenshot, not the
pair. ADR-028 § Amendment 2026-08-05 (#1336). Sibling of
§ "An occlusion layer ... must be darker than every ground it covers" below — same "what does it
actually composite over" question, asked of a surface rather than an occluder; keep the two
pointing at each other. (Ellipsis, not truncation, so a grep for the heading finds this pointer.)

**Measure a contrast ratio with the guard's own helpers** (`composite` /
`contrastRatio`, `DesignTokensTests+NightPalette.swift`) — an ad-hoc script that
quantizes the composited ground back to 0–255 lands off by enough to make a doc
comment disagree with the test asserting the same value. And **state which ground
each figure uses**: mixing per-site and worst-case grounds lets an aggregate
"before → after" range draw its two ends from different sites, which cannot be true.
ADR-028 § Amendment 2026-08-08.

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
on iOS 26 with `EXC_BAD_ACCESS` the instant the screen appears — a pure-SwiftUI
AttributeGraph fault stack with no app frame. A row with a *conditional* extra subview
survives; the same badge renders fine in a `LazyVStack` or `List`/`Form`.

**Two load-bearing lessons — the crash itself is now secondary:**

1. **Render crashes are invisible to `xcodebuild build` + the full unit suite** (both stay
   green). Only a UI test that navigates in and renders catches them. For a View-tree change
   on a screen the UI tests exercise, run at least one navigating UI test (cheapest that
   lands on ScenarioDetail: `PasturaUITests/BackGestureTests/testBackGestureFromScenarioDetailReturnsToHome`).
   Diagnose from `~/Library/Logs/DiagnosticReports/Pastura-*.ips` frames, not the XCUITest
   assertion message.
2. **These AttributeGraph crashes can be OS-build-specific and self-resolve** — this one
   stopped reproducing within a day and shipped with no code workaround. Before investing in
   one, confirm the repro on the **exact OS build AND a real device** (the sim misleads both
   ways). If it resurfaces, the candidate workarounds in order: extract the row into a
   concrete `View` struct → `.compositingGroup()` on the row → `LazyVStack` → drop the
   enumerated-`\.offset` `ForEach` shape → bisect the container
   `.background(...ignoresSafeArea())` half the fault stack names → `.geometryGroup()`.
   Full diagnostic write-up: #901.

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
A paired alias inside the content resolves against the *render* environment's
`colorScheme`: the value you inject, or **light** when you inject nothing, even
on an ambient-dark device.

**So the hazard is a consumer that omits the injection, not one that reads an
alias.** An export with no `.environment(\.colorScheme, …)` silently rasterizes
light — a dark-mode user's card comes out light (#1070). The question to ask of a
new fixed-appearance consumer is therefore **does it inject the appearance and
take it as a parameter?**, not "does it read a view that reads an alias".

**Apply**: capture `@Environment(\.colorScheme)` at the call site and drive the
view's palette from that value (an explicit `colorScheme` parameter), and set
`.environment(\.colorScheme, …)` on the rendered content for system-colored
subviews (SF Symbols, asset images). **The injection is the load-bearing half**,
and it is gated — `scripts/check_imagerenderer_injection.py`, in the pre-commit
hook and CI, fails any **app-target** file constructing an `ImageRenderer`
without injecting. Real-device dark-mode QA is still required; the simulator
misleads.

**Read `PasturaPalette.<token>.color`, never the `Color.*` alias, and treat that
as unconditional** — not belt-and-braces. An alias resolves correctly *today*,
but that was measured on one device and one OS minor; the raw read is what keeps
the export off a behaviour an SDK change can alter. Its in-repo cost meanwhile is
that `light` and `dark` collapse into each other, making the parameter you just
threaded inert. Do not treat a specific alias as fixed without checking
`PasturaDynamicPalette`, whose doc comment carries the current membership.

**What the gate does not cover.** It guards the injection half only. The token
tests assert `PasturaPalette` components *and* the aliases' own resolution, but
ADR-009 rules out snapshots, so any *new* fixed-appearance consumer needs its own
pin **on the alias half** — and nothing detects that pin's absence; three
mechanical guards for it were designed and refused (ADR-028 § "Revisit trigger"
bullet 1).
Today's pins are `HighlightShareCardPaletteTests` and `SheepAvatarPaletteTests`,
whose *invariance* arm derives its slots by **reflection** rather than a hand
list, so a stored property added later reading a paired alias reddens. Two pins
keep the reflection honest: an expected slot count (a computed-property refactor
would otherwise make it vacuous) and `colors.count == childCount` (a slot typed
`AnyShapeStyle` / `LinearGradient` / `UIColor` is invisible to `as? Color`).

Measurement, arms and controls: ADR-028 § Amendment 2026-08-06 (#1337).
Reference: `HighlightCardImageRenderer.render`, `HighlightShareCard`,
`HighlightCardPalette`, and `SheepAvatarPalette` for the avatar that card draws.

## An occlusion layer — shadow or scrim — must be darker than every ground it covers

A shadow or scrim is an occlusion cue, not a surface, so it needs a colour that
stays dark in **both** appearances. A paired alias inverts instead — `Color.ink`
resolves `nightInk` in dark — and the drop shadow becomes a pale **halo** under
the element it should sit beneath. Silent: no diagnostic, and the light build
looks correct.

The requirement is **not** "fixed in both appearances" — it is **darker than
every ground it covers**. Fixed is merely how you satisfy it when one value sits
below all of them; a fixed value still *lighter* than a night ground washes the
screen instead of dimming it, which is why the occluder family and
`PasturaPalette.scrim` are a warm near-black rather than `ink` or a moss tint.

**Apply**: inside `shadow(color:)` read `PasturaShadows` (design-system §4.3) or
`PasturaOccluderShadows` (§4.3.1) — both carry the same near-black and differ
only in geometry, so pick on that. Never `Color.<token>`, and **a raw
`PasturaPalette.<token>.color` is not sufficient either** (flagged at
`severity: error`): dropping the alias fixes the inversion but not the direction.
Reach for the raw palette only where an export needs a *chosen* appearance (the
`ImageRenderer` trap above) — the opposite reason, since an occlusion cue needs
*none*. A `.stroke` / `.overlay` hairline is the mirror case: it reads *against*
the surface, so it follows the appearance and keeps the alias.

**Ask what the element can actually sit on, not what the palette contains** — a
"floats over everything" component still only covers the grounds its visibility
predicate lets it reach. And hold the occluder/surface distinction: a scrim is
the occluder, while the card it fronts is a **surface** and stays paired — as
does `Color.<paired>.opacity(n)` used as a **wash under a surface**
(`screenBackground.opacity(0.78)` in `GameHeader` / `SimulationView`,
`ResultsView`'s status tints). Do not sweep those. Same test for any new
full-bleed fill: does it occlude, or is it a surface?

Enforced by the `shadow_color_occluder_family` custom SwiftLint rule — an
allowlist (a shadow tint must name `PasturaOccluderShadows` or `PasturaShadows`),
and **for the shadow half only**.

**A green run still does not mean "this shadow is dark enough."** The rule
matches a family **name**, so a member added to either family with a too-light
tint passes it — which is what `PasturaShadows` itself was until #1378, and what
the next addition could be. The scrim shape has no lint guard at all: one
instance, no stable syntax to key on, so a rule would be over-fitted. Tests carry
what lint cannot — `SimulationScrimStyleTests`, `PasturaOccluderShadowsTests` and
`PasturaShadowsTests` each assert the darker-than-every-ground requirement
against a **hand-maintained** ground list, which is the residual weakness: a
night ground added later and darker than the occluder value would not be covered
automatically.

Values, arithmetic and the measurements behind each revision: design-system §4.3
and ADR-028 § Amendment (#1284, #1373, #1378). Reference: `ModelPickerView`,
`InFlightSimulationIndicator`, `SimulationScrimStyle`, `PasturaOccluderShadows`,
`PasturaShadows`.

Sibling of § "Adding a `Color` design token"'s closing note — that one asks the same
"what does it composite over" question of a *presented surface* rather than an
occluder; keep the two pointing at each other.
