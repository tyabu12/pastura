---
paths:
  - "shared/**"
  - "tools/kmp-gate-spike/**"
---

# KMP Interop Rules

Traps of the ADR-023 KMP Engine migration (`shared/models`, `shared/engine`) — at the
Kotlin/Native (K/N) ↔ Swift boundary, and inside the Kotlin port itself. Three shapes:

- **Compile-time interop traps (Patterns 1–2)** — surface at the *Swift consumption* site when
  Swift code imports the generated `PasturaShared` XCFramework. On main that consumer is
  `tools/kmp-gate-spike/**` (6 Swift files `import PasturaShared`), which builds **nightly /
  `workflow_dispatch` only, not per-PR** (ADR-023 §6, decision B′); the iOS app (`Pastura/**`) does **not** consume the
  framework yet — that is Phase 3.0-gated. So these two are largely **forward-looking**: they were
  discovered in the W3 spike (PR #478) and bite again when Phase 3.0 K/N ↔ Swift integration
  begins. Both are path-scoped here because their **fixes are authored
  Kotlin-side in `commonMain`** (in scope) and the live gate-spike consumer (in scope) is where
  they compile-fail today.
- **Plan-time shape trap (Pattern 3)** — fires whenever a plan exercises a K/N type shape; fully
  in-scope for `shared/**` edits.
- **Port-time traps (Pattern 4)** — fire while writing the Kotlin port and its tests, with no Swift
  consumer involved; fully in-scope for `shared/**` edits.

> **Prompt-literal parity with the Swift original** is gate-enforced
> (`scripts/check-prompt-literal-parity.py`) and documented on the Swift side, in
> `engine.md` § "Prompt literals are paired with the Kotlin port" — deliberately *there*
> rather than here, because the contributor who breaks the invariant is the one editing
> `Pastura/Pastura/Engine/**`, and this file's `paths:` never reaches them. Read that
> section before touching a `pickLanguage` literal on either side.

> **When a `shared/**` port PR lands** (a `Phases/*.kt` added, or a stage advances), refresh
> [`docs/kmp-migration-status.md`](../../docs/kmp-migration-status.md). Its Wave B checklist is
> gate-enforced (`scripts/check-kmp-status.py`); the stage table + pointers are hand-maintained.
> This reminder is **inert for Stage 5's `Pastura/**` edits** (they don't load this file) — there
> the mechanical gate is the only guarantee.

## Pattern 1 — K/N exports carry no Swift `Sendable` conformance

K/N exports Kotlin classes through Obj-C interop. The generated
`@interface PasturaSharedFoo : PasturaSharedBase` carries **no `Sendable` conformance** — invisible
from Kotlin source alone, visible only by reading the generated `PasturaShared.h` header. Any code
crossing a K/N value type across an actor boundary then fails Swift 6 strict concurrency:

```
Sending 'snapshot' risks causing data races
Non-Sendable 'Pairing'-typed result can not be returned
  from actor-isolated instance method 'read()' to main actor-isolated context
```

**Workaround** (sound only for an immutable Kotlin `data class`):

```swift
extension PasturaShared.Pairing: @retroactive @unchecked Sendable {}
```

Soundness condition: **all** Kotlin fields must be `val`. For a mixed `var`/`val` class the
retroactive `@unchecked Sendable` is **unsafe** — do not add it.

**SOLE-declaration discipline**: exactly **one** `extension Foo: Sendable` per module — a duplicate
fails to link with a "redundant conformance" error. Document the canonical location inline so a
sibling declaration is never added.

**Long-term fix** (Phase 3.0 production integration): upstream the conformance to `commonMain`
(`expect`/`actual`, or a Swift-side bridge type) rather than keeping the retroactive extension. The
diagnostic fires at the **Swift use site**, not the Kotlin declaration — cf. `swift-isolation.md`,
which is always-loaded for the same "fires at use site" reason.

Source: W3 spike, PR #478 (`KNStateActor.read()` returning `Pairing` to a MainActor VM hit this on
first compile; three pre-impl critic rounds missed it because verifying it requires reading
`PasturaShared.h`, not the Kotlin source).

## Pattern 2 — `swift_name("Parent.Child")` does not reach Swift nested-type lookup

K/N annotates sealed-class subtypes with `__attribute__((swift_name("Parent.Child")))`:

```objc
__attribute__((swift_name("SimulationEvent.PhaseStarted")))
@interface PasturaSharedSimulationEventPhaseStarted : PasturaSharedSimulationEvent
- (instancetype)initWithPhaseType:(...)phaseType phasePath:(...)phasePath
  __attribute__((swift_name("init(phaseType:phasePath:)")));
```

The dot-syntax does **not** reach the Swift compiler's nested-type / nested-init lookup. Every call
form fails:

| Attempt | Error |
|---|---|
| `SimulationEvent.PhaseStarted(phaseType:, phasePath:)` | `type 'SimulationEvent' has no member 'PhaseStarted'` |
| `SimulationEventPhaseStarted(...)` (flat name) | `cannot find ... in scope` (the `swift_name` rename hides the pre-rename Obj-C name) |
| `SimulationEvent.SimulationCompleted.shared` (singleton via static) | same dot-syntax barrier on type lookup |

This blocks any Swift code that **constructs or pattern-matches** a Kotlin sealed-class subtype.
`SimulationEvent`, `TurnOutputError`, `SimulationError`, `YamlDecodeError` are all sealed classes.

**Contrast — why `PairingStrategy.roundRobin` works**: Kotlin **enum** entries export as
class-properties on the enum class (`@property (class, readonly) PairingStrategy *roundRobin`),
reached via `.roundRobin`. That is a different export surface from sealed-class subtype access.

**Fix** (must be Kotlin-side — not workaroundable in Swift): add an `object ...Factory` in
`commonMain` that flattens subtype construction through a **parent-typed** return signature:

```kotlin
// shared/models/src/commonMain/kotlin/com/pastura/models/SimulationEventFactory.kt
object SimulationEventFactory {
  fun phaseStarted(phaseType: PhaseType, phasePath: List<Int>): SimulationEvent =
    SimulationEvent.PhaseStarted(phaseType, phasePath)
  // ... one factory fn per sealed subtype
}
```

Swift then calls the flat `SimulationEventFactory.shared.phaseStarted(phaseType:, phasePath:)`.
**Pattern-matching** `if let p = event as? SimulationEvent.PhaseStarted` hits the same barrier —
cast via the parent-typed value and check a discriminator field, or add a Swift-friendly `kind`
enum getter on the parent.

Source: W3 spike, PR #478 (the planned third type `SimulationEvent.PhaseStarted` was pivoted to
`TurnOutput` after all three call forms failed; header-only inspection misleadingly suggests the
`swift_name` annotation works).

## Pattern 3 — grep the K/N type shape at plan time

When a plan item exercises a K/N type **shape** — enum case **count**, init-arg
cardinality/nullability, or `val` vs `var` — grep the actual Kotlin source before assuming the
shape supports the planned test:

```bash
cat shared/models/src/commonMain/kotlin/com/pastura/models/<TypeName>.kt
```

Verify: case count (enums), init-arg shape + nullability (data classes), property mutability. The
pre-impl `critic` frames coverage **themes** correctly but misses specific **cardinality** — e.g. a
plan called for `PairingStrategy` case-transition coverage, but `PairingStrategy` exports a single
case (`ROUND_ROBIN`), so that coverage was impossible; caught only at impl-prep grep, forcing a
mid-implementation pivot. Treat any case count as illustrative and re-verify live (the enums churn).

Same class of trap:

- **Default args don't cross** — Swift exports carry no Kotlin default-arg values; pass `nil`
  explicitly.
- **`val` is read-only in Swift** — a `data class val` property cannot be mutated in place; use
  `.copy(...)` or whole-instance reassignment.
- **Sealed-class export shape varies** — class vs enum-like surface differs (see Pattern 2).

## Pattern 4 — traps inside the Kotlin port (`commonMain`, `commonTest`, the port gates)

Patterns 1–3 are about the K/N *boundary*. These fire while writing the port itself, and most of
them compile or pass somewhere before failing where it counts.

**`commonMain` is not the platform stdlib.** An API present on JVM *and* Native is not necessarily
in the *common* stdlib. Every per-target compile (`compileKotlinIosSimulatorArm64`, `jvmTest`)
resolves it and passes — only `compileCommonMainKotlinMetadata` fails. **Run
`./gradlew :shared:engine:compileCommonMainKotlinMetadata` locally before pushing a port.** The
instances found so far carry their own why-comments at the call site (`RegexOption.DOT_MATCHES_ALL`,
`String.codePointCount`, `Map.toSortedMap`); the rule here is the task, not the list.

**Divergences from the Swift original** (the first fails loudly at the port site; the second is the
compile-clean one):

| Swift | Kotlin | Consequence |
|---|---|---|
| `SimulationError` is thrown directly | it is a `@Serializable sealed class`, **not** a `Throwable` — the engine throws it wrapped in `SimulationException` | unwrap before matching; a `catch` on the raw case does not compile |
| `1...0` traps | `1..0` is an **empty range** | a clamp port's failure mode flips from crash to silent zero-iteration, so a why-comment must say which engine it describes |

**The schema guard sits at a different place in each engine — a live behavioural divergence, not a
porting choice.** The two `hasAllExpectedKeys` helpers are identical (both reject a present-but-empty
expected key), and so is the `LLMCaller` empty-field branch (`LLMCaller.kt:160-164` says so in its
own comment). The divergence is **entirely in the parser**: Swift's happy path returns before any guard
(`JSONResponseParser.swift:95-97`) and applies it only on the salvage and post-repair paths
(`:105`, `:153`), whereas Kotlin applies it on every successful parse **when the phase declares an
`output:` schema** (`expectedKeys.isNotEmpty()`, `JSONResponseParser.kt:105`). So for a well-formed
but all-empty response (`{"note":""}`) to a schema-declaring phase:

| | Swift | Kotlin |
|---|---|---|
| parser | returns the empty output | throws `JsonParseFailed` |
| `LLMCaller` | `empty_field` retry; the **last attempt returns** the empty output | `parse_failed` every attempt → `RetriesExhausted` → turn-gate skip |

**Apply.** On the Kotlin side a handler's non-empty guard on a key the phase's `output:` **declares**
is defensive parity, unreachable via that path — so an "empty output doesn't erase X" test must
assert the **skip mechanism** (`TurnSkipped` emitted, no `AgentOutput`, prior value survives), never
the guard. Asserting the guard is coverage theater: revert it and the test stays green (the same rule
Swift-side is `testing.md` § "A regression test must drive the exact unguarded-path input"). The
declaration is validator-enforced for reflect→`note` and whisper→`statement`
(`ScenarioValidator.swift:264,278`), and the handler must actually pass the schema through
(`schema = OutputSchema.from(context.phase)`) — omit that and `expectedKeys` is empty again. For an
**undeclared** key — an optional `mood`, or any key on a schema-less phase — the parser guard never
runs and the handler guard *is* reachable: there a direct test is correct, and so is porting the
Swift one. ⚠️ The `TurnSkipped` assertion holds only **below** `TurnFailureGate.consecutiveSkipLimit`
— the tripping failure throws `TurnFailureLimitReached` and emits no `TurnSkipped`
(`TurnFailureGate.kt:77-80`), so a test driving that many consecutive empty turns fails the very
assertion this rule prescribes.

**Stage a new `.kt` before believing either gate.** `check-kmp-status.py` and the prompt-literal
parity gate both scope themselves to tracked files (correctly — `ci-workflows.md` § "Gate scripts"),
so an **untracked** new handler reads as "marked [x] but no ported .kt exists" / "no Kotlin
counterpart". The tracked directory is **`Phases/` with a capital P** (`KT_PHASES_DIR` is the
authority); macOS's case-insensitive filesystem lets a lowercase path work locally and fail the gate.

**A new `PhaseType` must be dispositioned in TWO Kotlin maps, neither compiler-caught.**
`PhaseDispatcher`'s `defaultHandlers()` decides whether the phase runs at all; `ConditionalHandler`'s
`subHandlers` decides whether it may run *inside a conditional branch*. Both are `Map` literals, so
omitting a case compiles — the failure is a mid-run throw, not a build error. Give the branch
decision the same allow/reject verdict as the Swift pair (`ScenarioValidator.validateBranch` +
`ConditionalHandler.subHandlers`), and remember that on this side there is **no `ScenarioValidator`**,
so `subHandlers` is the sole enforcement rather than a runtime backstop. The Swift-side cost axis —
which is where a phase is usually *introduced* — is `engine.md` § "Adding a new `PhaseType`"; that
rule's `paths:` never reaches a `shared/**`-only session, which is why the Kotlin half is restated
here rather than cross-referenced.

**A Models change can break `shared/engine`.** Adding a `SimulationError` case broke
`SimulationException`'s exhaustive `when`, and `:shared:models:jvmTest` alone is blind to it. Run the
CI pair — `:shared:models:jvmTest :shared:engine:jvmTest` — before pushing.

**Test authoring: `copy()` replaces a seeded map.** `SimulationState.initial` seeds `eliminated`
all-`false` for every agent, so `copy(eliminated = mapOf("Bob" to true))` leaves the others
**absent** — the test can no longer tell `== true` from `!= null`, and a wrong-polarity check stays
green against real state. Write the `false` entries explicitly, plus an absent-key case.

**Test authoring: `ScriptedLLMBackend` exhaustion is a harness fault, not a backend failure.** Running
out of scripts throws `IllegalStateException` by design, to flag an unintended extra call — so it is
**not** failure injection (a 1:1 port of Swift's `MockLLMService(responses: [])` fails unless the
handler's `catch` is widened, and a wide catch here swallows `CancellationException`, a JVM subclass of
`IllegalStateException`; script `TerminalStatus.Failed` instead), and it **pre-empts assertions** — a
`callCount` / `requests` assertion with no spare script is unreachable, so the test reddens without its
own assertion ever running. Over-script (`MAX_RETRIES + 1`) so the written assertion is the detector.
Decisive in §12 perturbation work, where "it reddened" IS the evidence: read *which* message fired.
Worked example: `NarrateHandlerTests` (#1331).
