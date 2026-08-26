---
paths:
  - "Pastura/Pastura/Views/**"
  - "Pastura/Pastura/App/**"
  - "Pastura/Pastura/PasturaApp.swift"
---

# SwiftUI / Swift 6 Traps

## Toolbar-hide API matrix (iOS 17 → 26)

| API | Bar removed | Chevron preserved | Swipe-back preserved |
|---|---|---|---|
| `.toolbar(.hidden, for: .navigationBar)` | Yes | No | **No — FB13484530 on iOS 17+** |
| `.toolbarVisibility(.hidden, for: .navigationBar)` (iOS 18+) | Yes | No | **No — same bug surface** |
| `.navigationBarBackButtonHidden(true)` | No (bar stays) | No (button hidden) | iOS 17–18: yes / **iOS 26: NO** |
| `.toolbarBackground(.hidden, for: .navigationBar)` | No (bar stays) | Yes | Yes |

iOS 26 root cause: with the back button hidden SwiftUI sees "no back affordance" and disables `interactivePopGestureRecognizer` system-wide. **Simulator-only QA is not load-bearing for these** — verify on a real device. To reclaim nav-bar space, **fill the bar** — `.toolbarBackground(.hidden, for: .navigationBar)` + `ToolbarItem(.principal)` — never `.toolbar(.hidden)`.

## TabView tab-bar SF Symbol auto-fill (iOS 15+)

A native `TabView` bar auto-applies the `.fill` variant to **every** tab icon, silently erasing an outline↔fill distinction you drive yourself. **Apply** `.environment(\.symbolVariants, .none)` on each tab `Image`; removing it re-fills every tab. Reference: `App/RootTabView.swift` (`symbolName(for:isActive:)`).

## NavigationStack in-place top-route replace (`AppRouter.replaceTop`)

Replacing the top route **in place** is not a push, and trips two **device-only** traps.

1. **Leaf identity is reused by stack position, not `Route` value**: a load-once view (`.task { guard viewModel == nil }`) keeps showing the PRIOR data, since `.task` never re-fires. **Fix**: `.task(id: scenarioId)` without the guard, building the new VM fully before assigning to avoid a `ProgressView` flash.
2. **Scroll offset is restored by nav position**, and `.id(scenarioId)` does not reset it. **Fix**: `ScrollPosition.scrollTo(edge: .top)` (iOS 18+, via `.scrollPosition(_:)`) lands at true offset 0 so a `.large` title re-expands; `ScrollViewReader.scrollTo(_:anchor:.top)` instead aligns one title-height below 0 and collapses the title.

Reference: `AppRouter.replaceTop`, `ScenarioDetailView.scenarioContent`.

**A tab root's `.task` also re-fires on every pop back to it** (measured iOS 26.5, #1565): pushing a route fires the root's `onDisappear`, the pop fires `onAppear`, and `.task` restarts. A root that builds its VM in `.task` without a `guard viewModel == nil` rebuilds it, and the state reset swaps the `ScrollView` out — losing scroll offset, search text and chip selection. Keep the VM; do only the cheap re-sync (installed snapshot) on re-fire. Reference: `SharedScenariosListView`.

## Production-side-effecting service: inject at View boundary

VM `init()` defaults run **in tests too**, so a production-only side-effecting service defaulted there is silently live in fixture tests: `SimulationRunner(detector: NLLanguageDetector())` fires on every output, drains the `MockLLMService` queue, and cascades into "Mock exhausted".

**Apply**: keep the VM default nil-equivalent (`SimulationRunner()`, `ContentFilter.passthrough`) and construct the real service at the consuming View. If adding `foo:` would change how `VMInit(repo: …)` behaves in tests, push the default down; pure-data services are exempt. Reference: `Views/Simulation/SimulationView.swift` (`SimulationRunner(detector:)` built at the View).

## SwiftUI drag & drop inside List / Form

`.dropDestination`'s **`isTargeted` closure never fires** inside `List` / `Form` rows on iOS 17–26 (FB12980427 / FB21980712): the action fires on release, so the feature looks wired up while hover feedback is dead. `DropDelegate.dropEntered` / `dropExited` also failed in `Form` rows.

Decide before designing: same-collection reorder → `.onMove` (deliberately single-`ForEach` only); cross-collection move → context menu; hover indicator → `ScrollView` + `LazyVStack`, or drop the requirement.

## `.accessibilityIdentifier` ordering around `.safeAreaInset`

An identifier applied **after** `.safeAreaInset(edge:)` scopes into the inset's subtree and **overrides** a child button's own identifier, so `app.buttons["Y"]` never resolves — the element exists, under the wrong id. It is scoped to the container the inset is attached to, not a blanket leak; put the identifier **before** the inset.

```swift
ScrollView { … }
  .accessibilityIdentifier("scenarioDetail.list")   // BEFORE — scroll content only
  .safeAreaInset(edge: .bottom) { actionBar }       // keeps its own button id
```

Reference: `ScenarioDetailView.swift`. To see which id an element carries, export the a11y snapshot per `uitest-traps.md`.

## iOS 26 `.confirmationDialog` renders as a mis-anchored popover

A `.confirmationDialog` **anchored to a control** (a `⋯`-`Menu` item, a row button) renders on iPhone as a popover whose arrow anchors to the **body centre**, pointing at empty space; no source-anchor API exists to fix it. **Use `.alert`** instead; it needs an explicit `Button(role: .cancel) {}` and supports `presenting:`. **Carve-out**: scene-level `isPresented`-driven *choice* dialogs are not control-anchored and render acceptably (`CellularConsentDialogModifier` in `PasturaApp.swift`, `ModelDownloadHostView.swift`). Reference: `Views/Results/ResultDetailView+Delete.swift`.

## iOS 26 Liquid Glass toolbar capsule — `.buttonStyle(.plain)` does NOT remove it

The **toolbar itself** wraps every `ToolbarItem` in a translucent capsule; `.buttonStyle(.plain)` only changes rendering *inside* it. Apply `ToolbarContent.hidingPasturaSharedBackground()` (`PasturaBackButton.swift`) to every `ToolbarItem` wrapping a custom Pastura control. **Verify on a real device**: the iOS 26 simulator suppresses the capsule even without the opt-out, so the simulator visual is misleading. Spec: `docs/design/design-system.md` § 5.8.1.

## Custom `Color` tokens don't work with `.foregroundStyle` dot-syntax

`.foregroundStyle(.muted)` and other `PasturaPalette`-derived tokens do not compile — the leading dot resolves against `ShapeStyle`. Write `Color.muted`.

## Adding a `Color` design token = 5 files; the 5th fails silently (workflow trap, not SwiftUI)

Miss the **5th** edit and at best only the standalone `Design tokens drift guard` CI job reddens; build, unit and lint stay green, so it is invisible locally:

1. `DesignTokens+ExtendedPalette.swift` — raw `PasturaColorValue(hex:)` token
2. `DesignTokens+SwiftUI.swift` — SwiftUI `Color` alias
3. `PasturaTests/Views/DesignTokensTests.swift` — assert it
4. `docs/design/design-system.md` § "2. カラートークン" — document it
5. `docs/design/ds/tokens.css` — CSS mirror

`scripts/check_design_tokens_css.py` owns the mirror check, but it is a **substring match on the hex**: a token whose value already appears under another name (`inkOnAccent` #FFFFFF vs `--bubble-bg`) has **no detector for its step-5 row**. Steps 1–3 assert the value *when done*, but nothing enforces that they were — verify by diff. Keep every `DesignTokens+*` filename inside that script's glob; renaming one out blinds the gate silently.

**A dark counterpart is a different, 6th-file shape**: the `night*` raw token in `DesignTokens+NightPalette.swift`, its `Color` alias, a `PasturaDynamicColor` entry in `DesignTokens+DynamicPalette.swift`'s `PasturaDynamicPalette` including its `all` registry, the light alias repointed to `PasturaDynamicPalette.x.color`, plus steps 3–5. Two silent gaps: the `all` registry's count assertion guards that list's documented size, **not** completeness, so an unregistered pair passes; and the CSS gate keys off `PasturaColorValue(hex:)` literals, so both pairing files are inert to it and only the new `night*` hex needs a `tokens.css` row. See ADR-028.

## `.sheet(item:)` — pass `Optional<Model>`, never `Int: Identifiable`

Pass the **model itself**. A project-wide `extension Int: Identifiable` applies to every `Int` and silently affects any code passing one where `Identifiable` is expected. Capturing an array index in the closure also risks out-of-bounds if the array mutates between trigger and body evaluation — look up `firstIndex(where:)` inside it.

## Never instantiate a ViewModel in a factory func / computed property

A VM created inside a View function or computed property gets a **fresh instance on every `body` re-evaluation**, silently wiping user state — `@Bindable` / `@Observable` references observe but do not own. Retain it with `@State` in a host view that creates it once (`.task { guard viewModel == nil … }`), showing a `ProgressView` until it exists.

## iOS 26 AttributeGraph crash — ForEach + glyph in a plain-ScrollView card

An unconditional subview (a glyph, a `.background(_, in: Capsule())` badge) added to a `ForEach` inside a plain `ScrollView` → eager `VStack` can crash with `EXC_BAD_ACCESS` as the screen appears — a pure-SwiftUI fault stack with no app frame.

1. **Render crashes are invisible to `xcodebuild build` and the whole unit suite**; only a UI test that navigates in and renders catches them. Cheapest onto ScenarioDetail: `BackGestureTests/testBackGestureFromScenarioDetailReturnsToHome`. Diagnose from `~/Library/Logs/DiagnosticReports/Pastura-*.ips`.
2. These faults can be OS-build-specific and self-resolve; confirm the repro on the **exact OS build and a real device** first.

## Re-projection resets `@State` — put run-scoped display state on the VM

Re-projecting an **already-running** `@Observable` VM into a **fresh** `View` (`SimulationSession.adoptIfMatching` re-mounts `SimulationView` onto a parked run, ADR-017) resets **every** `@State` in that view and its rows. Adopt rescues the *VM*; the fresh view clears the `@State`, so an "already revealed" latch living only in per-View or per-row `@State` **replays** and the user re-watches what they saw.

**Apply**: run-scoped display state that must survive a return-to-run belongs on the **surviving VM**, read back through a VM property — `SimulationViewModel.introRevealHasBegun`, `latestRowRevealCompleted`. Distinct from the fresh-VM `.resume` path (`isResumeEntry` / `effectiveCharsPerSecond`).

## `ImageRenderer` does not inherit the ambient environment

`ImageRenderer` rasterizes in a **default** environment — no ambient `@Environment`, notably `\.colorScheme`. No diagnostic; the bug is appearance-only and surfaces on a dark-mode device. `scripts/check_imagerenderer_injection.py` (pre-commit and CI) fails any app-target file constructing one without injecting, so capture `@Environment(\.colorScheme)` at the call site and pass it in as an explicit parameter.

**Inside the rendered content read `PasturaPalette.<token>.color`, never the `Color.*` alias.** An alias resolves correctly under an injection *today*, but the raw read keeps the export off a behaviour an SDK change can alter — and a palette building **both** families from aliases collapses them into one, since both resolve against the same injected scheme. Check `PasturaDynamicPalette`'s doc comment for membership before treating an alias as fixed.

**The gate covers the injection half only**: a new fixed-appearance consumer needs its own pin on the **alias** half, and nothing detects that pin's absence. Today's are `HighlightShareCardPaletteTests` and `SheepAvatarPaletteTests`; reference `HighlightCardImageRenderer.render`.

## An occlusion layer — shadow or scrim — must be darker than every ground it covers

An occlusion cue is not a surface: it needs a colour that stays dark in **both** appearances. A paired alias inverts — `Color.ink` resolves `nightInk` in dark — and the shadow becomes a pale **halo**. Silent: no diagnostic, and the light build looks correct.

The requirement is **darker than every ground it covers**, not "fixed in both appearances": a fixed value still *lighter* than a night ground washes the screen instead of dimming it, which is why the occluder family and `PasturaPalette.scrim` are a warm near-black rather than `ink`.

**Apply**: in `shadow(color:)` read `PasturaShadows` (design-system §4.3) or `PasturaOccluderShadows` (§4.3.1) — same near-black, differing only in geometry. Never `Color.<token>`, and **a raw `PasturaPalette.<token>.color` is not sufficient either**: dropping the alias fixes the inversion but not the direction. Ask what the element can actually sit on, not what the palette contains — a scrim occludes, while the card it fronts is a **surface** and stays paired, as does `Color.<paired>.opacity(n)` used as a wash under a surface (`GameHeader`, `SimulationView`, `ResultsView` status tints).

`shadow_color_occluder_family` allowlists the family **name**, for the **shadow half only**: **a green run does not mean "this shadow is dark enough"** — a too-light family member passes, and the scrim has no lint guard at all. `SimulationScrimStyleTests`, `PasturaOccluderShadowsTests` and `PasturaShadowsTests` assert the requirement against **hand-maintained** ground lists, so a night ground darker than #0B0C0A added later must be added to them by hand.

## Compile-checking `#if !targetEnvironment(simulator)` code

These blocks are excluded from every simulator build — what `scripts/xcodebuild.sh build` and `scripts/ui-tour.sh` produce — so a compile error in one survives a green local build. **CI is not blind to them**: `ci.yml`'s `release-build` job builds `-sdk iphoneos` on every iOS-touching PR, but in **Release configuration only**, so a block behind `#if DEBUG` *and* `!targetEnvironment(simulator)` is compiled by no CI job. The device build in `xcodebuild-cli.md` § Invocation is Debug and does reach it; layout still needs a real device.

**Don't pattern-match the directive**: `#if DEBUG || targetEnvironment(simulator)` is a *different* condition, not the complement — it is true in that Debug device build. The actual complement is the bare `#if targetEnvironment(simulator)`.
