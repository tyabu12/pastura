---
paths:
  - "Pastura/Pastura/**/*.swift"
---

# SwiftUI / Swift 6 Traps

Aggregation point for SwiftUI footguns and Swift 6 isolation quirks that surface during Pastura app development. Loaded only when editing Swift files in the app target. Cross-references to `navigation.md` (always-loaded) for AppRouter / `PasturaBackButton` mechanics — this file is the trap catalog, that one is the navigation pattern.

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
