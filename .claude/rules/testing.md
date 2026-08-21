---
paths:
  - "Pastura/PasturaTests/**"
---

# Testing Rules

## Swift Testing Parallelism

In `swift-testing-parallelism.md`, scoped so `tools/**` loads it too.

## Splitting a Suite Across Files (file_length 400-line cap)

Past SwiftLint's 400-line `file_length` limit, split a `*Tests.swift` with an `extension` of the
suite struct in a sibling `<Name>Tests+<Feature>.swift`, helpers at file scope. **Do not** create a
second `@Suite`: suites run in parallel and `.serialized` orders tests only *within* one, so a new
suite touching shared state (`Application Support` / `Caches` paths, singletons) races the original
— green locally, red on CI. Only the line count is linted; the remedy is not. Reference:
`ModelManagerTests+ProgressRegression.swift`.

## `.timeLimit` Trait on Every Suite (CI-Hang Diagnostic)

Every suite under `Pastura/PasturaTests/` **must** carry `.timeLimit(.minutes(1))` (Swift Testing's
minimum; `.seconds` is unsupported). Without it a hung test eats the CI job's whole wall clock,
corrupts the xcresult bundle, and names no test; nothing checks for its presence. An implicit suite
(no `@Suite`) has nowhere to hang the trait — promote it to explicit.

**Exception**: the env-gated integration suites (`OLLAMA_INTEGRATION`, `LLAMACPP_INTEGRATION`) skip
the suite cap — it resolves as the tighter bound and breaks local runs against real LLMs — and give
**every** `@Test` its own `.timeLimit(.minutes(2-5))` instead, or a hang is unbounded by both
(`OllamaIntegrationTests.swift`). Helper-only files need no trait.

## `-only-testing` false greens

A filtered run can execute fewer tests than you think while `xcodebuild` prints
`** TEST SUCCEEDED **` (`xcodebuild-cli.md` has the marker rule):

- **Individual `@Test` names may not match** Swift Testing's identifier scheme, and a zero-match
  resolves to success. Target the suite. XCTest is unaffected.
- **Suite-level means the TYPE name** — `@Suite("Display Name") struct FooTests` matches only
  `FooTests`; the display name resolves to zero tests.
- **`Executed 0 tests` in the XCTest stanza is cosmetic** (it counts `XCTestCase` subclasses only).
  The real count is the `✔ Test` / `Test run with N tests` markers; their absence is the real-bug
  signal — wrong path, not compiled, or a zero-match above.
- **Two `struct XxxTests` in one target silently halve the run**: the filter resolves to one, and
  the basename gate is per-target and blind to it. Find the twin
  (`rg -l 'struct XxxTests\b'`) and merge or rename.

## Parking a run mid-flight (teardown / cancel tests)

To hold `SimulationViewModel.run()` / `resume()` genuinely parked, call
`mock.suspendOnControllerAttach()` **before** starting the run: the `SuspendController` is
`.suspended` the instant the run attaches it, leaving no scheduling window. Do **not** park via
`throwSuspendedOnNextGenerate()` (the controller stays `.idle`) or arm `requestSuspend()` after
starting the **resume** path (its `.instant` Engine burst races the arm). Mechanism:
`parkRunMidFlight` in `SimulationViewModelStatusTests+ResumeContinuation.swift`.

## Wall-clock test bounds need CI headroom (20–30×)

Wall-clock assertions that pass locally fail on CI: the test job runs `-enableCodeCoverage YES` on a
shared runner and coverage bookkeeping is heavy for concurrency-heavy code — ~120 ms locally has been
seen at ~3.3 s. Keep the **lower** bound tight to local (it is the load-bearing check) and the
**upper** bound generous (`< 30.0` for a sub-second test), with the suite `.timeLimit` as the real
backstop. Better: inject an observable (counter, Clock stub).

## Expanding bundled data breaks count-pinning tests far away

Expanding a bundled data file silently breaks `count == N` canaries living far from it (blocklist,
registry, preset suites). Narrow `-only-testing` runs — the delegation default — never execute them,
so it stays invisible until a full run. In the same commit run
`rg 'count == |\.count\b' Pastura/PasturaTests --type swift` over the data's consumers, update the
canaries, and tell subagents to run the data's EXISTING suites too.

## Use exactly-representable IEEE-754 inputs in float-formatter tests

When pinning `String(format: "%.Nf", x)` or any platform float formatter, use exactly-representable
Doubles — halves (`1.5`, `12.5`, `0.25`, `0.125`). `1.85` is not: the stored value sits just off, so
`%.1f` rounds platform-dependently to `"1.8"` or `"1.9"` — green locally, red on CI. Avoid `1.1`,
`2.4`, `0.1`, `0.3`, `0.7`; for a boundary use `Decimal` or assert the real output.

## A regression test must drive the exact unguarded-path input

A regression test for a fix that adds a guard (`if case`, `guard let`, branch check) MUST construct
the input that would hit the **unguarded** path. Otherwise it is coverage theater: it passes both
pre- and post-fix, and a later refactor dropping the guard still passes. Plant that input, run the
method, then probe via **behavior**, never private state. Check first: *"If I revert the fix line,
does this test FAIL?"*
