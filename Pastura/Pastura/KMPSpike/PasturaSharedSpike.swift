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
/// H8 hypothesis verification (`@Observable` Swift class wrapping K/N
/// value types triggers SwiftUI invalidation) lives in the test target
/// as `PasturaTests/KMPSpike/H8BridgeTests.swift` (W3 PR-B). The earlier
/// compile-time smoke (`H8Smoke.verifyBridgeFires`) was absorbed there.
@MainActor
enum PasturaSharedSpike {
  /// Construct a `Pairing` from Swift, verifying the K/N init bridge
  /// preserves Kotlin's argument order (`agent1`, `agent2`, then the
  /// two `String?` action fields with null-default semantics).
  static func samplePairing() -> Pairing {
    Pairing(
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
  static let pairingStrategy: PairingStrategy = .roundRobin

  /// Construct a no-op `Phase` to exercise the nested-collection
  /// optionality (Q9 shim-LOC measurement). Phase's init exposes
  /// every field as an explicit parameter — including all optionals
  /// — so the spike's call site doubles as a smoke for that
  /// surface area.
  static func makeNoOpPhase(of type: PhaseType) -> Phase {
    Phase(
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

  // MARK: - Q9 expansion (W3 PR-C)
  //
  // Adds 3 K/N types to the production grep surface for Q9 measurement
  // (`grep -r 'import PasturaShared' Pastura/Pastura/`): Persona,
  // Scenario, SimulationEvent. Picked to maximize shape variety —
  // small required-only data class / top-level data class with nested
  // List / sealed sum-type with nested-class case — so post-W6 GO
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
  static func samplePersona() -> Persona {
    Persona(name: "Alice", description: "Test persona")
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
  static func sampleScenario() -> Scenario {
    Scenario(
      id: "spike-scenario",
      name: "Spike Scenario",
      description: "Q9 production-scaffolding fixture",
      language: "en",
      simulationLanguage: nil,
      agentCount: 1,
      rounds: 1,
      context: "Test context",
      personas: [samplePersona()],
      phases: [makeNoOpPhase(of: .speakAll)],
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
  ///
  /// **Originally planned as `SimulationEvent.PhaseStarted`**, pivoted
  /// to TurnOutput after discovering a load-bearing K/N export
  /// limitation:
  ///
  /// **Spike finding — `swift_name("Foo.Bar")` dot-syntax does NOT
  /// reach Swift compiler's nested-type / nested-init lookup**.
  /// The header declares `__attribute__((swift_name("SimulationEvent.PhaseStarted")))`
  /// on `@interface PasturaSharedSimulationEventPhaseStarted`,
  /// but EVERY tried callsite fails with `type 'SimulationEvent'
  /// has no member 'PhaseStarted'`:
  /// - `SimulationEvent.PhaseStarted(phaseType:, phasePath:)` — fails
  /// - `SimulationEventPhaseStarted(...)` (flat name) — fails
  ///   (`cannot find ... in scope`; the swift_name rename hides it)
  /// - `SimulationEvent.SimulationCompleted.shared` (singleton via
  ///   static property) — also fails (same dot-syntax barrier)
  ///
  /// This is a production K/N integration blocker for any code that
  /// needs to construct OR pattern-match sealed-class subtypes from
  /// Swift. W4 PR-A (Kotlin facade) MUST address this — likely by
  /// flattening sealed-class subtypes through `object` factories
  /// in `commonMain` that return the parent type. Tracked as a W4
  /// scope item in the PR-C checkpoint.
  static func sampleTurnOutput() -> TurnOutput {
    TurnOutput(fields: ["statement": "Hello from spike", "action": "cooperate"])
  }
}
