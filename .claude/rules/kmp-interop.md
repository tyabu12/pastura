---
paths:
  - "shared/**"
  - "tools/kmp-gate-spike/**"
  - "Pastura/Pastura/App/KMP/**"
---

# KMP Interop Rules

Traps of the ADR-023 KMP Engine migration at the Kotlin/Native (K/N) ↔ Swift boundary and inside
the Kotlin port. Since S5-1 the iOS app links and embeds the `PasturaSharedEngine` umbrella;
`Pastura/Pastura/App/KMP/` is the home of the K/N boundary adapters (ADR-023 §6 ruling (c)) and the
only place the umbrella may be imported (CLAUDE.md § Dependency Rules), so a Swift-side export break
reddens every per-PR iOS lane. `tools/kmp-gate-spike/**` keeps a twin of each adapter for the
nightly rung until S5-5: **a change to the §5.2 relay contract or an adapter's export-facing shape
lands in both copies in the same PR** — only `SuspendController` has a drift guard
(`tools/kmp-gate-spike/scripts/check-suspendcontroller-drift.sh`); for the rest this sentence is
the detector. Since S5-4 (#1681) the Kotlin engine runs **fresh** simulations behind
`FeatureFlags.sharedEngineEnabled` (a Diagnostics toggle, default off); the Swift `SimulationRunner`
stays the default run path until S5-5 flips it. `H7CrashTrigger.fire()` remains the S5-3
diagnostics-only crash probe reached from a double-gated Settings row (deleted in S5-5).
`App/KMP/SharedEngineRunner+AppRunPath.swift` and `SimulationEvent+SharedEngine.swift` are
app-module-only by construction — they name Swift twins the gate spike lacks, so they carry no
twin-parity obligation. The
Wave B checklist in `docs/kmp-migration-status.md` is gated by `check-kmp-status.py`; its stage
table and pointers are hand-maintained and are not.

## Pattern 1 — K/N exports carry no Swift `Sendable` conformance

The fix is Kotlin-side (upstream the conformance to `commonMain`). A retroactive
`extension Foo: @retroactive @unchecked Sendable` is sound **only** when every Kotlin field is
`val`, and exactly one declaration **per type** may exist per module (`App/KMP/SharedEngineRunner.swift`
carries the app module's four — `SimulationEvent`, `SimulationEngine`, `NoopEngineLogger`,
`SystemRandomSource`). Spell it on the qualified Kotlin type when a Swift twin exists, or
the conformance lands on the twin — Pattern 1b.

## Pattern 1b — a Kotlin type with a Swift twin is shadowed inside the app module

An in-module declaration shadows an imported one, so inside the `Pastura` module a bare
`SimulationEvent` binds to the **Swift** enum. 42 exported names collide (2026-08-30); re-derive
after a Kotlin bump:

```bash
grep -rhoE "^(public |sealed |data |abstract |open |value |expect |actual )*(class|interface|object|enum class) [A-Za-z]+" shared/models/src/commonMain shared/engine/src/commonMain shared/models/src/appleMain | awk '{print $NF}' | sort -u > /tmp/kn.txt
find Pastura/Pastura -name '*.swift' -print0 | xargs -0 grep -hoE "^(public |nonisolated |final |indirect |private |fileprivate )*(struct|class|enum|protocol|actor|typealias) [A-Za-z]+" | awk '{print $NF}' | sort -u > /tmp/sw.txt
comm -12 /tmp/kn.txt /tmp/sw.txt
```

Write `PasturaSharedEngine.X` at **every** use in `App/KMP/`, no typealias (an alias hides the
shadowing). Failure modes: a type-mismatch / redundant-conformance error at the call site (measured
on the retroactive extension in `App/KMP/SharedEngineRunner.swift`), or — the dangerous half — a
silent compile against the wrong type where the shapes coincide. The gate spike never hits this
(`KMPGateSpike` declares no twins), so a green nightly proves nothing about the app module.

## Pattern 2 — `swift_name("Parent.Child")` does not reach Swift nested-type lookup

Constructing a Kotlin sealed-class subtype from Swift fails on the dot syntax; Swift cannot work
around it — add a parent-typed `object …Factory` in `commonMain` and call that. Casting (`as?` /
`is`) does compile under the engine umbrella; construction was measured under the models one.
Re-measured 2026-09-05: constructing via the nested Swift name (e.g.
`PasturaSharedEngine.SimulationEvent.RoundStarted(round:totalRounds:)`) **compiles** under the
engine umbrella (`SimulationEventBridgeTests`) — the factory workaround applies only where
construction actually fails, not by default.

## Pattern 3 — grep the K/N type shape at plan time

Re-verify case count, init-arg cardinality / nullability, and `val` vs `var` against the Kotlin
source before planning coverage — the enums churn, and nothing else checks the plan against them.

K/N emits **no `@optional` section**: every member of an exported `interface` lands under
`@required`, defaulted or not. Adding a defaulted interface member therefore stays source-compatible
in Kotlin while breaking every Swift conformer, with no Swift author present and no per-PR lane to
catch it — fix the conformers in the same PR. Re-grep `@optional` in the regenerated
`PasturaSharedEngine.h` after a Kotlin bump: a section appearing flips this rule, and that edit
loads no rule file. See `LLMBackend.kt`; the app conformer `App/KMP/LLMServiceBackend.swift`
restates `knownTurnMarkers` as a computed forward for exactly this reason (the Kotlin default
does not cross K/N, #1472).

**A defaulted Kotlin parameter is not a default in Swift.** K/N drops default arguments and exports
one full-arity selector, so adding a defaulted constructor / function parameter stays
source-compatible in Kotlin while breaking **every** Swift construction site — same shape as the
`@optional` trap above, same nightly-only signal, same remedy: update the Swift callers in the same
PR. Measured on `SimulationEngine(detector:logger:)` (#1603), where the previously no-arg
`SimulationEngine()` gained two defaulted seams and each Swift caller had to spell out
`SimulationEngine(detector: nil, logger: NoopEngineLogger())`. Re-measured on `random:` (#1615): the
third seam moved the same gate-spike call site again, to
`SimulationEngine(detector:logger:random:)`. The same export shape also decides where a Kotlin
*top-level extension function* lands: it exports on a `<File>Kt` file facade rather than on the
protocol it extends, so a Swift conformer owes only the declared members — measured on
`RandomSource.index` / `unit`, which reach Swift as `RandomSourceKt` (#1615).

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

**A Models-layer message type is dual-landed, and the Kotlin format string is a *catalog key*.**
`ScenarioValidationMessage` (53) and `ScenarioLintMessage` (22) carry the Swift `String(localized:)`
literal verbatim as the key `rendering()` hands to the `expect` `localizedFormat`
(`MessageRendering.kt`); the Apple actual **falls back to the key**, so a Kotlin format that is no
longer a live catalog key renders English in the app with no runtime signal. A reword is a
**four-place** edit — Swift literal (source of truth) → catalog `ja` value via the normal sync →
Kotlin `rendering()` format → commonTest expected string. The detector is
`MessageCatalogCoverageTests` (`:shared:models:jvmTest`, run per-PR because `ci.yml`'s `kmp` filter
covers the catalog and both `*Message.swift`), with two blind spots stated on its KDoc:
it sees a reword only once `xcstringstool sync` has retired the old key (the
pre-commit hook skips that sync), and it compares specifiers, not meaning. Roster completeness is not
its job either — the commonTest count pins redden only if the hand transcription was updated too;
the `else`-free `when` in `swiftCaseNameOf` is the sole compile-time guard.
`check-prompt-literal-parity.py` still never scans `Models/`. The same class, with a sharper edge:
`Engine/PlaceholderAvailability.swift`
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

`shared/models` is in scope even when a task names only `shared/engine`: it builds no framework of
its own since ADR-023 §6 (b), but every one of its symbols is re-exported through the engine
umbrella, so its throws are the same crash class.

The gate is `verifyExportedThrowsAnnotations` in `shared/engine/build.gradle.kts` — it pins the
throwing entry points by `swift_name` and asserts each exports `error:` in the generated header
(that file's `Why the header and not the Kotlin source` comment has the reasoning). **The pin is
hand-kept**: a new throwing public entry point needs its pin added. `ScenarioCodec.encodeToString` /
`encodeToJsonElement` are deliberately outside it — un-annotated because the fixed encoder does not
reach `Json.encodeToString`'s throwing path, judged 2026-08-26, and invisible to any KDoc-triggered
check regardless. That is a reading of today's `Scenario` shape, so revisit it if the schema gains a
polymorphic field or a non-finite `Double`.

**`H7CrashProbe.crash` is the inverse carve-out (ADR-023 §6 S5-3, until S5-5).** Its whole
mechanism is the un-annotated throw this pattern warns about — the K/N termination *is* the probe.
Do not "fix" it with `@Throws`: the Swift call would become a catchable `throws`, `H7CrashTrigger`
would fall through to its `fatalError`, and the TestFlight crash would carry no Kotlin frame. The
same gate pins it the other way round (`exportedNonThrowingSelectors` asserts the selector exports
**without** `error:`), so the regression reddens — but the fix the gate's forward message prescribes
is the wrong one here; read the KDoc on `H7CrashProbe` first.

## Pattern 6 — a Kotlin throw's `localizedDescription` is the exception text, not the rendered message

`NSError.localizedDescription` on a bridged Kotlin throw carries the Kotlin exception's message,
not a `ScenarioValidationMessage`'s rendered, localized text — reading it directly silently
degrades the `ja` acceptance surface to English (or gibberish) instead of failing loudly. The
rendered message sits in `(error as NSError).userInfo["KotlinException"] as? SimulationException`;
unwrap that and call `.error` to get it. See `SharedEngineRunner.renderedValidationMessage(for:)`
and `SharedEngineAppRunPathTests`.
