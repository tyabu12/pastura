// Issue #220 W3 PR-A scope (a) — first iOS-side consumer of the KMP
// `PasturaShared.xcframework`. Lives outside the strict dependency-rule
// layers (Models/LLM/Engine/Data/Views/App) because the spike intentionally
// keeps KMP scaffolding off the production graph until W6 GO decision.
//
// Do NOT import this from production code. Reference from new spike-only
// callsites only. NO-GO path deletes `Pastura/Pastura/KMPSpike/` whole.

import PasturaShared

/// Spike-scope sandbox demonstrating iOS-side consumption of the KMP
/// `PasturaShared` Models layer (Issue #220 W3 PR-A).
///
/// Exercises three K/N → Swift interop surfaces per 1st pre-impl
/// critic Axis 8 (the single-`Pairing` proposal would have biased Q9
/// shim-LOC measurement low):
///
/// 1. **Data class init + property read** — `Pairing` (4 fields, two
///    optionals exercising K/N null-vs-omit semantics).
/// 2. **Enum case access** — `PairingStrategy.roundRobin` (Kotlin
///    `@SerialName("round_robin")` enum, K/N exports as class-property
///    `roundRobin` on the enum class).
/// 3. **Nested-collection optionality** — `Phase` with
///    `Map<String, String>?`, `List<String>?`, `List<Phase>?` fields.
///
/// **All types are spelled with the explicit `PasturaShared.` module
/// qualifier.** Pastura's own `Models/` layer defines Swift native
/// `Pairing`, `PairingStrategy`, `Phase`, `PhaseType`, `Persona`,
/// `Scenario`, `TurnOutput`, and `SimulationEvent` — without
/// qualification, the unqualified names resolve to the same-module
/// Swift types, NOT the K/N exports. W3 PR-A/B/C originally left
/// these unqualified; W4 PR-A Item 1 verification discovered they
/// were silently exercising Pastura's native Swift types, so the
/// spike's "validates K/N integration" evidence was hollow. Each
/// callsite is now explicitly qualified to ensure K/N code paths
/// actually run; this also makes the swift_name dot-syntax barrier
/// (which IS real on flat mangled names — `swift_name` hides them)
/// invisible to the spike, leaving sealed-class subtype access as
/// the only K/N-specific concern.
///
/// H8 hypothesis verification (`@Observable` Swift class wrapping K/N
/// value types triggers SwiftUI invalidation) lives in the test target
/// as `PasturaTests/KMPSpike/H8BridgeTests.swift` (W3 PR-B). The earlier
/// compile-time smoke (`H8Smoke.verifyBridgeFires`) was absorbed there.
@MainActor
enum PasturaSharedSpike {
  /// Construct a `Pairing` from Swift, verifying the K/N init bridge
  /// preserves Kotlin's argument order (`agent1`, `agent2`, then the
  /// two `String?` action fields with null-default semantics).
  static func samplePairing() -> PasturaShared.Pairing {
    PasturaShared.Pairing(
      agent1: "Alice",
      agent2: "Bob",
      action1: nil,
      action2: nil
    )
  }

  /// Reference the `@SerialName("round_robin")` enum case via Swift's
  /// camelCase mapping. K/N exposes enum entries as class-readonly
  /// properties on the enum class itself (visible via the framework
  /// header as `@property (class, readonly) PairingStrategy *roundRobin`).
  static let pairingStrategy: PasturaShared.PairingStrategy =
    PasturaShared.PairingStrategy.roundRobin

  /// Construct a no-op `Phase` to exercise the nested-collection
  /// optionality (Q9 shim-LOC measurement). Phase's init exposes
  /// every field as an explicit parameter — including all optionals
  /// — so the spike's call site doubles as a smoke for that
  /// surface area.
  static func makeNoOpPhase(of type: PasturaShared.PhaseType) -> PasturaShared.Phase {
    PasturaShared.Phase(
      type: type,
      prompt: nil,
      outputSchema: nil,
      options: nil,
      pairing: nil,
      logic: nil,
      template: nil,
      source: nil,
      target: nil,
      excludeSelf: nil,
      subRounds: nil,
      condition: nil,
      thenPhases: nil,
      elsePhases: nil,
      probability: nil,
      eventVariable: nil
    )
  }

  // MARK: - Q9 expansion (W3 PR-C, extended W4 PR-A)
  //
  // Adds K/N types to the production grep surface for Q9 measurement
  // (`grep -r 'import PasturaShared' Pastura/Pastura/`): Persona,
  // Scenario, TurnOutput, SimulationEvent. Picked to maximize shape
  // variety — small required-only data class / top-level data class with
  // nested List / sealed sum-type with nested-class case — so post-W6 GO
  // production integration has reference patterns spanning the K/N
  // export quirks the spike has surfaced.
  //
  // **Production usage routes through `ScenarioLoader`, NOT these
  // factories.** Spike-scope only.

  /// Persona is a Kotlin `data class Persona(val name: String, val
  /// description: String)` — both fields **required Strings**, NO
  /// Optional. Q9 measurement: minimal 2-required-arg data class
  /// export. The Optional bridge surface is already covered by
  /// `samplePairing`'s `action1` / `action2` (`String?` with
  /// `null` default) — duplicating it here would be redundant.
  ///
  /// Persona name "Alice" is the cross-fixture convention for
  /// spike scaffolding (see also `sampleScenario`'s persona array).
  static func samplePersona() -> PasturaShared.Persona {
    PasturaShared.Persona(name: "Alice", description: "Test persona")
  }

  /// Scenario's 11-arg init exercises the **deep nested data class**
  /// surface — `personas: List<Persona>`, `phases: List<Phase>`,
  /// `extraData: Map<String, AnyCodableValue>`. Kotlin defaults on
  /// `simulationLanguage` and `extraData` DO NOT bridge to Obj-C
  /// (K/N export collapses parameter defaults at the C boundary),
  /// so all 11 args must be passed explicitly from Swift.
  ///
  /// **Q9 insight — primitive bridging**: the header declares
  /// `agentCount:(int32_t)agentCount rounds:(int32_t)rounds`, but
  /// K/N's Swift interop layer wraps `int32_t` as Swift `Int` (NOT
  /// `Int32`). The Swift call site passes `Int` literals — wrapping
  /// in `Int32(1)` would fail compilation with "cannot convert
  /// 'Int32' to 'Int'".
  ///
  /// Minimum viable factory: 1 persona + 1 phase + `agentCount: 1`
  /// satisfies the documented invariant `agentCount == personas.size`.
  /// Adding more personas / phases would cascade additional
  /// fixture-construction LOC without changing the K/N bridge
  /// surface exercised.
  static func sampleScenario() -> PasturaShared.Scenario {
    PasturaShared.Scenario(
      id: "spike-scenario",
      name: "Spike Scenario",
      description: "Q9 production-scaffolding fixture",
      language: "en",
      simulationLanguage: nil,
      agentCount: 1,
      rounds: 1,
      context: "Test context",
      personas: [samplePersona()],
      phases: [makeNoOpPhase(of: PasturaShared.PhaseType.speakAll)],
      extraData: [:]
    )
  }

  /// TurnOutput is a 1-arg `data class TurnOutput(val fields:
  /// Map<String, String>)` — exercises the **K/N
  /// `Map<String, String>` bridge** (Swift `[String: String]` literal
  /// auto-bridges cleanly to `NSDictionary<NSString *, NSString *>`,
  /// unlike `Map<String, primitive>` which requires `KotlinInt` /
  /// `KotlinBool` boxing — see `SimulationState.scores` for an
  /// example of that boxed-primitive case).
  static func sampleTurnOutput() -> PasturaShared.TurnOutput {
    PasturaShared.TurnOutput(fields: ["statement": "Hello from spike", "action": "cooperate"])
  }

  /// SimulationEvent is the canonical sealed-class spike fixture —
  /// constructed via direct dot-syntax against the swift_name-named
  /// subtype, with explicit `PasturaShared.` module qualification.
  ///
  /// **The fix is qualification, NOT a Kotlin facade.** W4 PR-A Item 1
  /// re-diagnosed PR-C's documented "swift_name dot-syntax barrier"
  /// finding — the actual root cause is **Swift module shadowing**:
  ///
  /// `Pastura/Pastura/Models/SimulationEvent.swift` defines a Swift
  /// `enum SimulationEvent` with associated-value cases. Within the
  /// Pastura/ target the unqualified name resolves to that enum, not
  /// to PasturaShared's K/N-exported `@interface SimulationEvent`. The
  /// Swift enum has no `PhaseStarted` nested type — hence the error
  /// `type 'SimulationEvent' has no member 'PhaseStarted'`. PR-C had
  /// inferred this was a K/N export barrier and pivoted to TurnOutput
  /// rather than discovering the qualification fix.
  ///
  /// Verified-working access surface (locked into
  /// `Pastura/PasturaTests/KMPSpike/KNDotSyntaxAccessTests.swift` as a
  /// regression guard for the K/N export shape):
  ///
  /// - `PasturaShared.SimulationEvent.SimulationCompleted.shared` —
  ///   sealed-class `object` singleton via swift_name dot-syntax.
  /// - `PasturaShared.SimulationEvent.PhaseStarted(phaseType:, phasePath:)`
  ///   — sealed-class data-class subtype constructor.
  /// - `event as? PasturaShared.SimulationEvent.PhaseStarted` —
  ///   subtype-cast pattern match for production consumers.
  ///
  /// The genuine K/N export limitation is the flat-mangled-name path
  /// (`PasturaSharedSimulationEventPhaseStarted(...)`) which `swift_name`
  /// correctly hides — intentional, not a regression. Production K/N
  /// integration in the Pastura/ target therefore does NOT need
  /// `commonMain` facade objects for sealed-class subtypes; consumers
  /// disambiguate locally via `PasturaShared.` qualification.
  static func sampleSimulationEvent() -> PasturaShared.SimulationEvent {
    // Note the explicit `PasturaShared.` module qualifier on BOTH the return
    // type and the constructor — Pastura's own `Models/SimulationEvent.swift`
    // (a Swift `enum`) shadows the K/N-exported class of the same name when
    // unqualified, and Swift's `Pastura.SimulationEvent` enum has no nested
    // `PhaseStarted` type. The qualifier picks the K/N class explicitly so
    // its swift_name dot-syntax nested types are visible.
    PasturaShared.SimulationEvent.PhaseStarted(
      phaseType: PasturaShared.PhaseType.speakAll,
      phasePath: [0]
    )
  }
}
