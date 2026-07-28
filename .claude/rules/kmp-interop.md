---
paths:
  - "shared/**"
  - "tools/kmp-gate-spike/**"
---

# KMP Interop Rules

Traps at the Kotlin/Native (K/N) ↔ Swift boundary of the ADR-023 KMP Engine migration
(`shared/models`, `shared/engine`). Two shapes:

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
