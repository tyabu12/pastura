---
paths:
  - "Pastura/PasturaTests/**"
  - "Pastura/PasturaUITests/**"
  - "tools/**"
---

# Swift Testing Parallelism

Split out of `testing.md` so `tools/**` can load it without pulling that file's
other ~14 KB.

## `.serialized` is intra-suite only

`@Suite(.serialized)` orders tests **within** one suite. Separate top-level suites
still run concurrently, so it does not isolate a suite from its neighbours. For
that, run the package with `swift test --no-parallel` — and wire the flag into
every invocation that matters (CI step **and** the README command), because
nothing in the manifest enforces it.

**Apply**: use `.serialized` for suites whose tests create `SimulationRunner` or
any type spawning `Task` + `AsyncStream` (concurrent teardown crashes the test
process). Reach for `--no-parallel` additionally when a suite *measures* anything.
Handler tests with `MockLLMService` need neither.

## Timing assertions: ratio against an in-test control, never an absolute

An absolute bound (`#expect(ticks >= 10)`) encodes one machine's speed and the
contention level of the day, so adding an unrelated suite can fail it. Measure a
control in the same test and compare rates. Motivating case: the ADR-023 gate
spike's MainActor liveness probe fell to `ticks → 3` the moment a fifth suite
began overlapping it (#1172).

Pairs with `testing.md` § "Wall-clock test bounds need CI headroom".
