---
paths:
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/**"
---

# Swift Testing Parallelism

## `.serialized` is intra-suite only

`@Suite(.serialized)` orders tests **within** one suite. Separate top-level suites still run
concurrently, so it does not isolate a suite from its neighbours; for that, run the package with
`swift test --no-parallel` and wire the flag into every invocation that matters (CI step **and**
README command), because nothing in the manifest enforces it.

**Apply**: use `.serialized` for suites whose tests create `SimulationRunner` or any type spawning
`Task` + `AsyncStream` (concurrent teardown crashes the test process), and add `--no-parallel` when
a suite *measures* anything. Handler tests with `MockLLMService` need neither.

## Timing assertions: ratio against an in-test control, never an absolute

An absolute bound (`#expect(ticks >= 10)`) encodes one machine's speed and the contention of the
day, so an unrelated suite can drop the observed rate and fail it. Measure a control in the same
test and compare rates. See `testing.md` § "Wall-clock test bounds need CI headroom".
