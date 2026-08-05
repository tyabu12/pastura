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
locally (first hit PR #953):

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
steps above assume a brand-new value. A dark pair adds: the `night*` raw token, which goes in
`DesignTokens+NightPalette.swift` rather than step 1's file; its `Color` alias; a
`PasturaDynamicColor` entry in `DesignTokens+DynamicPalette.swift`'s
`PasturaDynamicPalette` (including its `all` registry — its count assertion guards
that list's documented size, not completeness: an unregistered pair still passes), the
light alias repointed from `PasturaPalette.x.color` to `PasturaDynamicPalette.x.color`, plus
steps 3–5. Note the CSS gate keys off `PasturaColorValue(hex:)` literals, so **both** pairing
files (`+DynamicColor.swift`, the mechanism; `+DynamicPalette.swift`, the table) are inert to
it — only the new `night*` hex needs a `tokens.css` row. Keep every `DesignTokens+*` filename
inside `check_design_tokens_css.py`'s glob; renaming one out blinds the gate silently (each
file's own header says so). See ADR-028.

**Choosing the value: a token-pair ratio is not a prediction about a *presented* surface.** For a
sheet / overlay fill, the comparand is the **composited** backdrop — the presentation dims what is
behind and not the surface itself, which can flip the sign. `nightPage` sits 1.099 *below*
`nightBackground` by design and renders 1.031 *above* its own backdrop. Judge such a value against a
device screenshot, not the pair. ADR-028 § Amendment 2026-08-05 (#1336). Sibling of
§ "An occlusion layer ... must be darker than every ground it covers" below — same "what does it
actually composite over" question, asked of a surface rather than an occluder; keep the two
pointing at each other. (Quoted with an ellipsis, not truncated, so a grep for the heading finds
this pointer too.)

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

**The `Color.*` aliases make this sharper, not milder.** Most of them resolve
light↔dark against the ambient interface style, so reading one inside
`ImageRenderer` content means "whatever appearance the renderer resolved" — and
an explicitly light or dark export becomes unexpressible. The rest are fixed
(unpaired light tokens, `night*`, time-of-day, chart), so a token-styled view
otherwise rasterizes in one appearance regardless of device. **The paired set
grows with each gate-1 slice** — do not treat a specific alias as fixed without
checking `PasturaDynamicPalette`, whose doc comment carries the current
membership and its slice-by-slice provenance.

**Apply**: pass the appearance in **explicitly** — capture
`@Environment(\.colorScheme)` at the call site, and drive the view's palette
from that value (an explicit `colorScheme` parameter) reading
**`PasturaPalette.<token>.color`, never the `Color.*` alias** — the raw palette
values are fixed sRGB, which is exactly the property an export needs. Also set
`.environment(\.colorScheme, …)` on the rendered content for any system-colored
subviews (SF Symbols, asset images). Real-device dark-mode QA required — the
simulator misleads.

**What catches a regression here**: the token tests assert `PasturaPalette`
components *and* the aliases' own resolution, and both consumers carry a pin —
`HighlightShareCardPaletteTests` and `SheepAvatarPaletteTests`. Since #1337 the *invariance*
arm of each derives its slots by **reflection**, not a hand list (the mapping
assertions still name slots, correctly — a mapping needs the name), so a stored property added
later reading a paired alias reddens; before that it did not, measured. Two pins
keep the reflection honest: an expected slot count (a computed-property refactor
would otherwise make it vacuous) and `colors.count == childCount` (a slot typed
`AnyShapeStyle` / `LinearGradient` / `UIColor` is invisible to `as? Color`).

ADR-009 rules out snapshots, so any *new* fixed-appearance consumer still needs
its own equivalent pin or it is unguarded — **nothing detects its absence**. An
enumeration guard for that was designed and refused (ADR-028 § "Revisit trigger"
bullet 1): it cannot redden on the shape that actually happened, below.
Reference consumers: `HighlightCardPalette`, and `SheepAvatarPalette` for the
avatar that card draws.

**The consumer is not always the view you migrated.** A component a
fixed-appearance consumer *draws* inherits the constraint without appearing in
any consumer list — pairing §2.5 silently un-pinned `HighlightShareCard`'s
`SheepAvatar` (#1319). Ask not "does a fixed-appearance consumer read this
token" but "does one read a **view** that reads it".

Reference: `HighlightCardImageRenderer.render` + `HighlightShareCard` (#1070).

## An occlusion layer — shadow or scrim — must be darker than every ground it covers

A shadow is an occlusion cue, not a surface, so it wants a colour that stays
dark in **both** appearances. A paired alias inverts instead: `Color.ink`
resolves `nightInk` (#E8E5D8) in dark, `Color.moss` → `nightMoss`,
`Color.mossInk` → `nightMossInk` (#C6CBB1) — the drop shadow becomes a pale
**halo** under the element it should sit beneath. Silent: no diagnostic, and
the light build looks correct.

design-system §4.3 already takes this position — `PasturaShadows.tight` /
`.soft` carry a fixed moss-tinted `rgba(90,100,60,…)` and do not pair. The three
ad-hoc `shadow(color:)` sites were simply written before the aliases paired.

**Apply**: read `PasturaOccluderShadows` (design-system §4.3.1) inside
`shadow(color:)`. Never `Color.<token>` — and since #1377, **a raw
`PasturaPalette.<token>.color` is not sufficient either** and is flagged at
`severity: error`: dropping the alias fixes the inversion but not the direction,
which is the #1373 defect and the whole subject of the paragraphs below.
(`PasturaShadows` also passes lint — that is the #1378 debt, not an
endorsement; do not reach for it on a new ground-floating element.) Reach
for the raw palette only where an export needs a *chosen* appearance (the
`ImageRenderer` trap above) — the opposite reason, since an occlusion cue needs
*none*. A `.stroke` / `.overlay` hairline is the mirror case: it reads *against*
the surface, so it follows the appearance and keeps the alias.

**A full-bleed dimming scrim is the same trap wearing different clothes**, and
it is louder — but it also corrects the rule above. `Color.ink.opacity(0.4)`
behind the model-load overlay composited to **#6D6D64** over the #1B1D17 night
ground, *lighter* than what it covers, so it washed the screen pale. Swapping in
the raw palette fixes the direction and **still fails the requirement**: `ink`
#2D2E26 over that ground gives #22241D, lighter again, and over `nightBubble` it
moves one channel by one step. `0.4·C + 0.6·ground` cannot fall below `ground`
when `C` is lighter than it.

So the requirement is not "fixed" — it is **darker than every ground it covers**.
Fixed is merely how you satisfy that when one value sits below all of them, which
is why `PasturaPalette.scrim` is a warm near-black (#0B0C0A at 0.4: #979692 in
light, #10110E in dark) rather than `ink`.

**A shadow does not get away with a lighter value either** — an earlier revision
of this section said it did, on the grounds that shadows are drawn against local
surfaces rather than the app ground. That premise is false for any element that
*floats on* the ground. Measured directly under the ModelPicker card, a raw,
fixed `moss` at 0.22 rendered **#2B2F24** on a #1B1D17 ground: a green glow. The
three such sites now read `PasturaOccluderShadows` (design-system §4.3.1), which
reuses the scrim's #0B0C0A (#1373).

Two consequences worth carrying:

- **A near-black cannot keep the moss tint**, so §4.3's "彩度は苔系" is explicitly
  excepted for this family rather than silently violated. Arithmetic: §4.3.1.
- **`PasturaShadows.tight` / `.soft` share the defect** and are deferred on blast
  radius, **not** because it is small — `.soft` lifts about half what the glow
  above did. Do not read their survival as endorsement, and do not copy their
  tint onto a new ground-floating element. Measurements and the four consumers:
  **#1378**.

**Ask what the element can actually sit on, not what the palette contains.** A
"floats over everything" component still only covers the grounds its visibility
predicate lets it reach — the first value here was rejected against a ground no
member could ever meet. Worked instance: ADR-028 § Amendment 2026-08-05 (#1373).

The distinction to hold: the scrim is the **occluder**; the card it fronts
(`.regularMaterial`, its `Color.ink` title, its `Color.muted` subtitle) is a
**surface** and stays paired. Same test for any new full-bleed fill — does it
occlude, or is it a surface?

`Color.<paired>.opacity(n)` used as a **wash under a surface** — `GameHeader`'s
and `SimulationView`'s `screenBackground.opacity(0.78)`, `ResultsView`'s status
tints — is the surface case and correctly stays paired. Do not sweep those.

Enforced by the `shadow_color_occluder_family` custom SwiftLint rule — **for the
shadow half only**. As first written (then named `shadow_color_paired_alias`) it
was a denylist keyed on a leading-dot `Color.*` and so never saw the shape that
actually shipped three times: a raw
`PasturaPalette.<lightToken>.color.opacity(…)`, fixed but above the ground.
#1377 inverted it to an **allowlist** — a shadow tint must name
`PasturaOccluderShadows` or `PasturaShadows`, and anything else is flagged — so
the syntactic gap is closed.

**A green run still does not mean "this shadow is dark enough."** `PasturaShadows`
is on that allowlist while measured *above* the night ground (#1378, in the
consequences above), so the rule certifies family membership and nothing more.
The scrim shape has no lint guard at all: one instance, no stable syntax to key
on, so a rule would be over-fitted.

Tests carry what lint cannot — `SimulationScrimStyleTests` and
`PasturaOccluderShadowsTests` each assert the darker-than-every-ground
requirement against a **hand-maintained** ground list, which is the residual
weakness: a night ground added later and darker than #0B0C0A would not be
covered automatically. Reference: `ModelPickerView`,
`InFlightSimulationIndicator`, `SimulationScrimStyle`,
`PasturaOccluderShadows`; ADR-028 § Amendment (#1284, #1373).

Sibling of § "Adding a `Color` design token"'s closing note — that one asks the same
"what does it composite over" question of a *presented surface* rather than an
occluder; keep the two pointing at each other.
