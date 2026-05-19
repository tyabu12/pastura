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
| `.navigationBarBackButtonHidden(true)` | No (bar stays) | No (button hidden) | iOS 17–18: yes / **iOS 26: NO** (PR #352) |
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
