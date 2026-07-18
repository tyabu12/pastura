# `kmp-gate-spike` — ADR-023 §6 Stage-2 gate consumer

The Swift half of the KMP Stage-2 GO/NO-GO gate. It links the Kotlin
`shared/engine` slice through a real `PasturaSharedEngine.xcframework` and
exercises **both** ADR-023 boundary contracts end to end:

- **§5.1 event/control** — `SharedEngineRunner` rebuilds an
  `AsyncStream<SimulationEvent>` from the Kotlin `onEvent` callback and relays
  `pause` / `resume` / `cancel` / `notifyLLMResumed` back through `RunHandle`.
- **§5.2 inference** — `ScriptedStreamingBackend` is a Swift `LLMBackend`
  *actual* driving a real `AsyncThrowingStream`, so the gate measures the
  genuine Swift→Kotlin inference seam. A Kotlin-side mock would not satisfy the
  gate; that is the whole point of this package.

Companion PRs: **PR-A** #1137 (macosArm64 target + XCFramework export),
**PR-B** #1152 (Kotlin-side slice). Umbrella: #501.

## Why this is a separate package

Decision **B′** (ADR-023 §6, resolved on #1135) states the invariant:

> No per-PR lane acquires an XCFramework dependency — not the iOS xcodebuild,
> not the root `Package.swift` harness build, not a dev `swift build`.

The repository-root `Package.swift` **is** the ADR-013 `pastura-harness`
manifest (`tools/harness/` has no manifest of its own). The `harness-build` CI
job runs bare `swift build` and `swift test` against it — see
`.github/workflows/ci.yml`, steps *"Build harness package"* / *"Run harness
package tests"*, gated on `needs.changes.outputs.ios != 'false'`. Bare
`swift build` builds **every** target in a manifest, so adding a
`.binaryTarget` there would make every iOS-touching PR require an assembled
XCFramework — option *(B-root)*, which ADR-023 §6 rejects by name.

The converse also holds, which is why a nested package is safe: every target in
the root manifest carries an explicit `path:`, so this directory is not swept
into the root graph, and a root `swift build` / `swift test` does not recurse
into it. Both directions are asserted per-PR by the `kmp-gate-isolation` job in
`.github/workflows/ci.yml` — ungated, because a gated guard would skip on
exactly the PRs that only touch the manifest.

**What that job does not cover**, stated so the guarantee is not read wider than
it is: it greps the root `Package.swift`, which is the common cause for two of
B′'s three lanes (the harness build and a dev `swift build`). The **iOS
xcodebuild** lane is not checked by it — an XCFramework added to
`Pastura.xcodeproj` would violate B′ without touching any manifest. The grep
also strips whole-line comments only, so a trailing `// … .binaryTarget …`
still trips it. Both gaps are tracked in #1171.

**Do not consolidate this into the root manifest.** If a future change makes
that look attractive, the constraint above is the reason it is not.

## Assemble first

The `.binaryTarget` is a **staged** artifact, absent from a fresh checkout
(`Frameworks/` is gitignored). Stage it once per checkout, and again whenever
`shared/engine` or `shared/models` changes:

```bash
tools/kmp-gate-spike/scripts/stage-framework.sh          # debug (default)
tools/kmp-gate-spike/scripts/stage-framework.sh release
```

That wraps the Gradle task and copies the result into `Frameworks/`:

```bash
./gradlew :shared:engine:assemblePasturaSharedEngineDebugXCFramework --no-daemon
# → shared/engine/build/XCFrameworks/debug/PasturaSharedEngine.xcframework
```

(There is no `scripts/kmp/` helper on `main` — the `assemble-xcframework.sh`
that ADR-023 §6 mentions lives on the retained `feature/kmp-spike-models`
branch and is Stage-5 salvage, not a `main` tool.)

Then, from the repository root:

```bash
swift build --package-path tools/kmp-gate-spike
swift test  --package-path tools/kmp-gate-spike --no-parallel
swift run   --package-path tools/kmp-gate-spike kmp-gate-bench
```

`--no-parallel` is not optional hygiene. The Pattern 6 probe asserts a floor on
MainActor ticks during a paced run, and a sibling suite draining its own paced
scripts on the same machine starves it — observed directly: adding one suite
took the probe from passing to `ticks → 3` against a floor of 10. The suites
carry `.serialized`, but that trait orders tests *within* a suite and does not
stop two suites from overlapping. `kmp-nightly.yml` passes the same flag.

**Failure mode to expect on an unstaged checkout.** A local-path binary target
is resolved when the package *graph* loads, not when the manifest is
evaluated — `Package.swift` compiles fine, and `swift build` is what fails,
naming the missing `Frameworks/PasturaSharedEngine.xcframework` path. If you
are debugging such an error, that path is the thing to search for; the manifest
is not at fault.

Why staged rather than referenced in place: SwiftPM resolves a target path
relative to the package root and rejects one that escapes it, so
`../../shared/engine/build/...` is not addressable from here.

## The `SuspendController` copy

`Sources/KMPGateSpike/SuspendController.swift` is a **verbatim copy** of
`Pastura/Pastura/LLM/SuspendController.swift`, not a re-implementation, and the
`suspendcontroller-drift` job in `.github/workflows/ci.yml` fails **per-PR** if
the two diverge. It is a plain bash/awk/diff comparison of two tracked files, so
it needs neither the XCFramework nor a macOS runner — which is why it does not
live with the rest of this package's checks in `kmp-nightly.yml` (#1171).

The same SwiftPM path-escape rule that forces the staged framework also forbids
referencing the real file from this package. A hand-written stand-in was
rejected: the real controller carries a single-awaiter `precondition`, an
idempotent `resume()` on `.idle`, and a non-obvious self-resume race fix
(`if Task.isCancelled { extractStoredContinuation()?.resume() }`). A
re-implementation that dropped any of those would still pass a happy-path relay
test — so the gate would report **§5.2 invariant 3** (lost-wakeup safety) as
witnessed while actually testing a strictly weaker object. A byte-identical copy
plus a divergence guard removes that failure surface.

**Do not edit this copy.** Change the real file and re-run the staging of this
one; the guard exists to make an accidental one-sided edit loud.

## Gate measurements

`kmp-gate-bench` produces the ADR-023 §6 figures. Two of the five are
deliberately not measured here, and both carve-outs are recorded on #501 and in
the ADR rather than left implicit. Figures and their reading:
ADR-023 § "11. Amendment 2026-07-18" and
[#501](https://github.com/tyabu12/pastura/issues/501#issuecomment-5010845072).

```bash
# From the repository root — (i)/(iii) resolve source paths against the cwd
# and error out rather than reporting a zero if run from elsewhere.
swift run --package-path tools/kmp-gate-spike kmp-gate-bench
```

| Measurement | Status |
|---|---|
| (i) event-boundary ergonomics, incl. the threading clause | measured here — counted from source; threading clause via the Pattern 6 probe |
| (ii) inference-boundary chunk-relay overhead + suspension-relay round-trip | measured here — ≈20 µs/chunk, ≈50 µs round trip; one macOS host, **`debug` XCFramework** (the staging default), spreads not bounds |
| (iii) K/N shim-budget on the Engine-consuming surface | measured here — 24 declarations, test-side shims included |
| (iv) SKIE-vs-vanilla | **documented evaluation only** — no SKIE integration |
| (v) kotlinx.serialization round-trip parity on `TurnOutput`/`OutputSchema` | **one-sided**, via checked-in golden JSON (see below) |

### Measurement (v) — golden JSON

(v) is a two-sided parity claim, but the Swift `Codable` types live in
`Pastura/Pastura/Models/` — unreachable from here for the same path-escape
reason. It is therefore taken as a Kotlin-side **decode** of golden JSON emitted
by the ADR-013 harness, which does reuse that directory in place. What stays
unmeasured is the reverse direction: Swift decoding Kotlin's output. That
belongs to Stage 3's parity harness.

```bash
# Regenerate after ANY change to the Swift Models types (from the repo root):
swift run pastura-harness emit-golden --write
# Drift gate — the same check CI runs:
swift run pastura-harness emit-golden --check
```

The artifacts live with the types they describe, in `shared/models`, not in
`shared/engine` as the module split might suggest — `TurnOutput` and
`OutputSchema` are `shared/models` types, and the suite that pins what Kotlin
*emits* (`OutputSchemaSerializationTests`) is already there. They sit in
`commonTest` rather than `jvmTest` so the K/N rung is covered too, which is why
the goldens are a generated Kotlin source file rather than a `.json` resource:
`commonTest` cannot read resources.

- Generator: `tools/harness/Sources/PasturaHarnessKit/GoldenFixtureEmitter.swift`
- Generated: `shared/models/src/commonTest/kotlin/com/pastura/models/SwiftGoldenJson.kt`
- Consumer: `shared/models/src/commonTest/kotlin/com/pastura/models/SwiftGoldenParityTests.kt`

**Result: `TurnOutput` passes, `OutputSchema` does not.** Kotlin cannot decode
Swift's `OutputSchema` bytes at all — the two sides disagree on enum tagging, on
the second case's name (`choice` vs `enumeration`), and on whether it carries an
options payload. The parity suite asserts the rejection rather than skipping the
type, so the finding cannot decay silently. Detail and consequences: #501.

Per ADR-023 §6, only (ii)'s performance **absolutes** are host-sensitive
(macOS vs iOS K/N share a Darwin/arm64 runtime and memory model). Figures are
recorded as macOS-host; iOS-device absolutes belong to Stage-5 QA.

## Where this code goes at Stage 5

ADR-023 §10 calls `SharedEngineRunner` and the backend adapter **permanent** —
§6 rejects the throwaway-branch option *(C)* precisely because it would discard
them. They are written here to survive, so their destination is worth recording
now rather than deciding under merge pressure at Stage 5:

- **`SharedEngineRunner`** replaces the shell role of today's
  `Pastura/Pastura/Engine/SimulationRunner.swift`, so `Engine/` is its natural
  home.
- **The `LLMBackend` actual** wraps `LlamaCppService`, so `LLM/` is its natural
  home. `ScriptedStreamingBackend` here is the *scripted* stand-in for it; the
  real adapter is Stage-5 work.

**Open Stage-5 input, deliberately not resolved here.** Putting
`SharedEngineRunner` in `Engine/` creates an `Engine/ → PasturaSharedEngine`
edge that CLAUDE.md's Dependency Rules table does not currently describe (it
reads `Engine/ → depends on LLM and Models. NEVER depends on Data.`). Whether
the K/N framework is modelled as a new layer, folded into `Models`, or given its
own row is a Stage-5 decision that needs the ADR and the table updated together.
Flagging it, not answering it.

See also the Stage-5 two-umbrella landmine in ADR-023 §6: `PasturaShared`
(models-only) and `PasturaSharedEngine` must never link into one binary.
