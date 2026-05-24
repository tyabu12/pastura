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
}
