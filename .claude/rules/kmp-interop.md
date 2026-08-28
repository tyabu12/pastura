---
paths:
  - "shared/**"
  - "tools/kmp-gate-spike/**"
---

# KMP Interop Rules

Traps of the ADR-023 KMP Engine migration at the Kotlin/Native (K/N) ↔ Swift boundary and inside
the Kotlin port. The iOS app does not consume the generated XCFramework yet; the only Swift
consumer, `tools/kmp-gate-spike/**`, builds nightly rather than per-PR, so a Swift-side break's
first signal is a red nightly. The Wave B checklist in `docs/kmp-migration-status.md` is gated by
`check-kmp-status.py`; its stage table and pointers are hand-maintained and are not.

## Pattern 1 — K/N exports carry no Swift `Sendable` conformance

The fix is Kotlin-side (upstream the conformance to `commonMain`). A retroactive
`extension Foo: @retroactive @unchecked Sendable` is sound **only** when every Kotlin field is
`val`, and exactly one such declaration may exist per module.

## Pattern 2 — `swift_name("Parent.Child")` does not reach Swift nested-type lookup

Constructing a Kotlin sealed-class subtype from Swift fails on the dot syntax; Swift cannot work
around it — add a parent-typed `object …Factory` in `commonMain` and call that. Casting (`as?` /
`is`) does compile under the engine umbrella; construction was measured under the models one.

## Pattern 3 — grep the K/N type shape at plan time

Re-verify case count, init-arg cardinality / nullability, and `val` vs `var` against the Kotlin
source before planning coverage — the enums churn, and nothing else checks the plan against them.

K/N emits **no `@optional` section**: every member of an exported `interface` lands under
`@required`, defaulted or not. Adding a defaulted interface member therefore stays source-compatible
in Kotlin while breaking every Swift conformer, with no Swift author present and no per-PR lane to
catch it — fix the conformers in the same PR. Re-grep `@optional` in the regenerated
`PasturaSharedEngine.h` after a Kotlin bump: a section appearing flips this rule, and that edit
loads no rule file. See `LLMBackend.kt`.

## Pattern 4 — traps inside the Kotlin port (`commonMain`, `commonTest`, the port gates)

**Roster completeness is a pin, not a proof.** `KClass.sealedSubclasses` is JVM-only and
`commonTest` must run on `macosArm64`, so a roster there can only be an asserted count plus an
`else`-free `when`. Say so where you write the pin, or the next reader takes it for a proof. See
`ScenarioValidationMessageTests.kt`.

**`1..0` is an empty range, `1...0` traps.** Porting a clamp flips its failure mode from a Swift
crash to a silent zero-iteration, so a why-comment must name which engine it describes.

**Apply: assert the skip mechanism, not the guard.** A handler's non-empty guard on a key the
phase's `output:` **declares** is defensive parity, unreachable from the exhaustion path, so an
"empty output doesn't erase X" test must assert `TurnSkipped` emitted, no `AgentOutput`, and the
prior value surviving. Asserting the guard is coverage theater — revert it and the test stays green
(Swift twin: `testing.md` § "A regression test must drive the exact unguarded-path input"). The
handler must pass the schema through (`schema = OutputSchema.from(context.phase)`); omitting it
empties `expectedKeys` and disables the skip rule. For an **undeclared** key the rule is off by
design and the guard *is* reachable — a direct test is correct there. `narrate` is permanently
undeclared and catches around its own call, so a throw is swallowed: the round loses its narration
with no `TurnSkipped` and no breaker increment.

⚠️ That assertion holds only **below** `TurnFailureGate.consecutiveSkipLimit`: the tripping failure
throws `TurnFailureLimitReached` and emits no `TurnSkipped` (`TurnFailureGate.kt`), so a test
driving that many consecutive empty turns fails the very assertion this rule prescribes.

**Stage a new `.kt` before believing either gate.** `check-kmp-status.py` and the prompt-literal
parity gate scope themselves to tracked files, so an **untracked** handler reads as "marked [x] but
no ported .kt exists" — a misleading message, not a refusal. The tracked directory is **`Phases/`
with a capital P** (`KT_PHASES_DIR` is the authority); macOS's case-insensitive filesystem lets a
lowercase path work locally and fail the gate.

**A new `PhaseType` must be dispositioned in TWO Kotlin maps, neither compiler-caught.**
`PhaseDispatcher.defaultHandlers()` decides whether the phase runs at all; `ConditionalHandler`'s
`subHandlers` decides whether it may run *inside a conditional branch*. Both are `Map` literals, so
an omission compiles and fails as a mid-run throw. `ScenarioValidator.kt` now gates
`SimulationEngine.run` via `preflightGate` (D3, #1591), so `subHandlers` is a backstop behind it,
not the sole run-path enforcement — but the validator checks scenario-level and phase-field
semantics, not phase-dispatch reachability, so a `PhaseType` omitted from either map still needs
this fix.

**A Models change can break `shared/engine`**, and `:shared:models:jvmTest` alone is blind to it —
run the CI pair `:shared:models:jvmTest :shared:engine:jvmTest` before pushing. Likewise every
per-target compile and `jvmTest` passes while only `compileCommonMainKotlinMetadata` fails, so a
green local run is not evidence.

**Test authoring: `copy()` replaces a seeded map.** `SimulationState.initial` seeds `eliminated`
all-`false` for every agent, so `copy(eliminated = mapOf("Bob" to true))` leaves the others
**absent** — the test can no longer tell `== true` from `!= null`, and a wrong-polarity check stays
green. Write the `false` entries explicitly, plus an absent-key case.

**Test authoring: `ScriptedLLMBackend` exhaustion is a harness fault, not a backend failure.**
Running out of scripts throws `IllegalStateException` by design, so it is not failure injection
(script `TerminalStatus.Failed` instead; a widened `catch` also swallows `CancellationException`, a
JVM subclass of it) — and it **pre-empts assertions**: a `callCount` assertion with no spare script
is unreachable, so the test reddens without its own assertion running. Over-script
(`MAX_RETRIES + 1`) so the written assertion is the detector. See `NarrateHandlerTests.kt`.

**A parity fixture's `responses` list is positional, so a retry-count divergence must have its
surplus reabsorbed.** The retrying engine consumes the *following* turns' answers — valid
same-schema JSON, so it often succeeds with shifted content instead of diverging as intended. Pick
the placement before scripting: only the run's **last** LLM call (surplus falls into the replay
padding) or a compensating burn on the following indices works, so give the divergence a scenario
whose last turn has nothing downstream — `parity_structural.yaml` exists for that.

**A Kotlin mirror of a Swift `Codable` wire shape matches `JSONEncoder` in none of three behaviours
by default.** Sorted keys apply at *every* depth; `nil` is omitted rather than written as `null`; an
integral `Double` drops its `.0`. The third bites silently: `TranscriptComparator` compares
`JsonPrimitive.content` as **text** and `EventLine.t` is non-optional on every line, so a bare
`JsonPrimitive(0.0)` diffs 100 % of them. Build the line as a `JsonObject` rather than a
`@Serializable data class` — that fixes all three — and write it against a measured Swift line,
never the fixtures' observed lines: a field no fixture populates is the one that bites later.
`RunLogTests.fullyPopulatedLinePinsTheWireShape` is that measurement.

**A Models-layer message type is dual-landed, and no gate compares the two sides.**
`check-prompt-literal-parity.py` only scans `Engine/` + `LLM/` files containing `pickLanguage`, so
it never reaches `Models/`. Reword a literal in `Pastura/Pastura/Models/*Message.swift` and the
Kotlin twin plus its commonTest pins stay stale *and agree with each other* — nothing reddens on
either side. The Swift file is the source of truth; a reword is a three-file hand edit (Swift, the
`.kt`, the commonTest expected string). Applies to `ScenarioValidationMessage` (53) and
`ScenarioLintMessage` (21). The same class, with a sharper edge: `Engine/PlaceholderAvailability.swift`
→ `shared/engine/.../PlaceholderAvailability.kt` is a data map the Swift linter and two editor views
**consume today**, so it keeps moving — a new `PhaseType` or handler-supplied token is a three-file
hand edit (Swift, the `.kt`, its commonTest), and only the Swift union-guard test notices a Swift-side
miss. The ledger pairs `PORT` rows by name alone; it does not diff them.

## Pattern 5 — a KDoc `@throws` does not reach K/N; only `@Throws` does

An exception thrown from a function K/N exported **without** the `@Throws` annotation is not
converted to a Swift error — it terminates the calling process. The annotation is what turns the
exported selector into a `…error:(NSError**)` one, which Swift imports as `throws`. A KDoc
`@throws` line reaches the header as a comment and changes nothing, so the two are easy to mistake
for each other: the documentation reads correct while the export is a crash path.

Annotate the **declaration** that gets exported. `internal` members are emitted into no header at
all, so an `internal` implementation of a `public` interface needs nothing — but Kotlin does not
inherit the annotation, so one that later goes `public` needs its own. `YamlCodec.decode` carries
the annotation on the interface for exactly this reason.

`shared/models` is in scope even when a task names only `shared/engine`: it builds its own iOS
frameworks *and* is re-exported through the engine umbrella, so its throws are the same crash class.

The gate is `verifyExportedThrowsAnnotations` in `shared/engine/build.gradle.kts` — it pins the
throwing entry points by `swift_name` and asserts each exports `error:` in the generated header
(that file's `Why the header and not the Kotlin source` comment has the reasoning). **The pin is
hand-kept**: a new throwing public entry point needs its pin added. `ScenarioCodec.encodeToString` /
`encodeToJsonElement` are deliberately outside it — un-annotated because the fixed encoder does not
reach `Json.encodeToString`'s throwing path, judged 2026-08-26, and invisible to any KDoc-triggered
check regardless. That is a reading of today's `Scenario` shape, so revisit it if the schema gains a
polymorphic field or a non-finite `Double`.
