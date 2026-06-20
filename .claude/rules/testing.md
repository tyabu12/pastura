---
paths:
  - "Pastura/PasturaTests/**"
---

# Testing Rules

## Swift Testing Parallelism

Tests that create `SimulationRunner` (or any type that spawns `Task` + `AsyncStream`
internally) **must** use `@Suite(.serialized)` to avoid test-process crashes from
concurrent Task/AsyncStream cleanup. This applies to integration tests that consume
`AsyncStream<SimulationEvent>` via `for await`.

Individual unit tests (e.g., handler tests with `MockLLMService`) are safe to run
in parallel because they await the handler directly without AsyncStream.

## Splitting a Suite Across Files (file_length 400-line cap)

When a `*Tests.swift` file exceeds swiftlint's 400-line `file_length` limit,
split by adding an `extension` of the suite struct in a sibling file named
`<Name>Tests+<Feature>.swift` (Apple's `Type+Feature.swift` convention).

**DO NOT** create a new `@Suite` for the split. Swift Testing runs `@Suite`s
in parallel by default — `.serialized` only orders tests *within* a suite,
not across them. A new suite that touches shared state (filesystem paths
under `Application Support` / `Caches`, in-process singletons, etc.) will
race against the original. Local runs may squeak through on faster machines;
CI's slower runner is where the race surfaces.

**Pattern:**

```swift
// ModelManagerTests.swift — original suite, slimmed under 400 lines
@Suite("ModelManager", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct ModelManagerTests {
  func makeSUT(...) -> ModelManager { ... }   // NOT `private` — see below
  @Test func ...
}

// ModelManagerTests+ProgressRegression.swift — sibling
extension ModelManagerTests {
  @Test func downloadCompletesWhenDownloaderSkipsTerminalProgress() async {
    let sut = makeSUT(...)   // Calls into the original file's helper
  }
}
```

**Access modifier:** Helpers the extension calls (`makeSUT`, etc.) must be
at **internal** access (default — drop `private`). `private` members are
only visible to extensions in the *same file*; sibling-file extensions
cannot see them. Widening to module-internal is contained because the test
target is its own module.

**Helpers** (mocks, observation collectors) live at file scope in the new
sibling file — they don't need to be members of the suite struct.

**History:** PR #157 (Issue #72) introduced this rule after the throttle
regression test was originally split into a standalone `@Suite`. The new
suite raced against `ModelManagerTests/modelNotDownloaded()` on the shared
model file path; it passed locally but failed on CI.

## `.timeLimit` Trait on Every Suite (CI-Hang Diagnostic)

Every Swift Testing suite under `Pastura/PasturaTests/` **must** carry
`.timeLimit(.minutes(1))` (Swift Testing's minimum; `.seconds` is not supported).
A hung test then fails individually at the 1-minute boundary with a
`failed (timed out)` line naming the specific test, instead of silently
eating the CI job's 15-minute wall-clock and corrupting the xcresult bundle.
This is a load-bearing diagnostic — do not remove it from existing suites,
and do not skip it when adding new ones.

Apply to both suite forms:

- **Explicit `@Suite(...)`**: include the trait alongside any existing traits.
  ```swift
  @Suite(.timeLimit(.minutes(1)))                              struct FooTests { ... }
  @Suite(.serialized, .timeLimit(.minutes(1)))                 struct BarTests { ... }
  @Suite(.serialized, .timeLimit(.minutes(1))) @MainActor      struct BazTests { ... }
  @Suite("Display Name", .serialized, .timeLimit(.minutes(1))) struct QuxTests { ... }
  ```
- **Implicit suite** (`struct XxxTests` with `@Test` methods and no `@Suite`):
  Swift Testing treats it as an implicit suite; without the attribute there
  is no place to hang the trait. Promote to explicit `@Suite`:
  ```swift
  @Suite(.timeLimit(.minutes(1)))
  struct XxxTests { @Test ... }
  ```

**Exceptions (document inline when skipping):**

- Integration suites gated out of CI by env var (`OLLAMA_INTEGRATION`,
  `LLAMACPP_INTEGRATION`) are exempt from the suite-level 1-minute cap
  because it would be resolved as the tighter bound and silently break
  local integration runs against real LLMs. Each `@Test` in these suites
  **must** carry its own `.timeLimit(.minutes(2-5))` sized for real-LLM
  inference — without a per-test bound, a hung integration test would be
  unbounded by *both* rules. (See `OllamaIntegrationTests.swift` and
  `LlamaCppIntegrationTests.swift` for the current shape.)
- Helper-only files (no `@Test` / `@Suite` declarations, e.g.
  `EngineTestHelpers.swift`) don't need the trait.

**If a unit test legitimately needs more than 1 minute:** override at the
`@Test` level (`@Test(.timeLimit(.minutes(N))) func ...`). Swift Testing
resolves the tightest-bound among suite + test traits, so a per-test widen
is unusual — consider first whether the test is doing too much (split it,
mock heavier work, etc.).

**History:** PR #134 (Issue #131) introduced this rule after a
cancel-before-store race in `SuspendController.awaitResume()` silently
hung one test for 15 minutes on CI. See `memory/project_ci_timeout_investigation.md`.

## `-only-testing` and Swift Testing

When using `-only-testing` with `xcodebuild`, prefer **suite-level** targeting
(e.g., `PasturaTests/SimulationRunnerTests`) over individual test names
(e.g., `PasturaTests/SimulationRunnerTests/myTest`). Individual Swift Testing
(`@Test`) functions may not match reliably, causing tests to silently not run
while `xcodebuild` still reports `TEST SUCCEEDED`.

**Why:** Swift Testing uses a different identifier scheme than XCTest. `xcodebuild`
resolves zero matching tests and reports success (0 failures = `TEST SUCCEEDED`).
This does NOT affect XCTest (`func testXxx()` in `XCTestCase`), which individual
targeting works correctly for.

**Verify:** Always check the test count in the output to confirm tests actually ran.

## Duplicate Suite Names Silently Halve `-only-testing`

Two `struct XxxTests` declarations across files in the same target make
`-only-testing PasturaTests/XxxTests` resolve to **only one** of them —
the other suite silently doesn't run, and xcodebuild still prints
`** TEST SUCCEEDED **`. Distinct from the individual-`@Test` trap above:
suite-level targeting is the mitigation there, but doesn't help when the
suite *name itself* is duplicated.

**Diagnostic:** if `Test run with N tests` reports fewer tests than the
file you're looking at contains, locate the twin with
`rg -l 'struct XxxTests\b' Pastura/PasturaTests` and merge into one suite
(preferred — readers assume "DataError tests live in DataErrorTests.swift")
or rename one (PR #448).

## Test-Target `FRAMEWORK_SEARCH_PATHS` for Framework Imports

When a test file `import`s a framework from `Pastura/Frameworks/`, the
PasturaTests target needs its **own** `FRAMEWORK_SEARCH_PATHS` build
setting (Debug + Release blocks in the pbxproj) — compile-time
swiftmodule discovery does not inherit from the app target's settings,
even though `TEST_HOST` already covers *runtime* symbol resolution via
the host app. Do NOT also link the framework into the test target's
Frameworks build phase — redundant, and it complicates Embed & Sign
reasoning.

No framework consumer exists on main today; the first arrives with the
KMP integration (#501). The spike-branch wiring that surfaced this is
PR #474 (#220 W3 PR-B).

## MockLLMService Usage

- Always call `try await mock.loadModel()` before running any code that calls
  `LLMService.generate()`.
- Provide exactly the number of responses expected. `MockLLMService` throws when
  exhausted — this is intentional to catch over/under-provisioning.
- Use `mock.capturedPrompts` to verify prompt content in tests.

## Parking a run mid-flight (teardown / cancel tests)

To hold a `SimulationViewModel.run()` / `resume()` genuinely parked mid-flight
(e.g. to test a raw `Task.cancel()` teardown), arm the controller at attach
time: call `mock.suspendOnControllerAttach()` **before** starting the run. That
puts the live `SuspendController` in `.suspended` the instant the run attaches
it — before the first generate — so the run parks deterministically, with no
scheduling window.

Do **not**:

- Use `mock.throwSuspendedOnNextGenerate()` as a park. It only schedules a
  `.suspended` throw; the controller stays `.idle`, `awaitResume()` returns
  immediately, and the run keeps running (that helper is for unit-testing the
  suspend-retry loop, not parking).
- Arm `sut.suspendController?.requestSuspend()` from the test **after** the run
  starts on the **resume** path. `run()` has an awaited `createSimulationRecord`
  hop before its first generate that yields a window, but `resume()` does not —
  its `.instant` Engine burst (unbuffered `AsyncStream`, no backpressure) races
  the arm and the run completes → `.completed` flake (#707).
- Route through `pauseSimulation()` when the test pins the `!isCompleted`
  teardown branch (#673) — it sets `didPersistPaused` and shifts the ladder.

Full mechanism + the wait helper live in `parkRunMidFlight`
(`SimulationViewModelStatusTests+ResumeContinuation.swift`) and the
`suspendOnControllerAttach()` doc-comment — point there, don't re-derive.

## Shared Test Helpers (`EngineTestHelpers.swift`)

- **`EventCollector`**: Thread-safe event collector for `@Sendable` emitter closures.
  Do not capture mutable local variables (e.g., `var events: [...]`) in `@Sendable`
  closures — Swift 6 strict concurrency rejects this as a potential data race.
- **`makeTestScenario(agentNames:rounds:phases:context:extraData:)`**: Convenience
  factory for test scenarios. Defaults: 3 agents (`["Alice", "Bob", "Charlie"]`),
  1 round, empty phases. Use this instead of constructing `Scenario` manually.
- **`makePhaseContext(scenario:phaseIndex:llm:collector:)`**: Convenience factory
  for `PhaseContext`. Bundles scenario, phase, LLM, and emitter for handler tests.
  Use this instead of constructing `PhaseContext` manually.
