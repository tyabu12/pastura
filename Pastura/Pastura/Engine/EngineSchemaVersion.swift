import Foundation

/// The engine's capability version — the single authoritative declaration of
/// "what capabilities this build's engine can execute" (ADR-020 D1).
///
/// This is the Swift realization of the ADR's `ENGINE_SCHEMA_VERSION`: the
/// constant is exposed as ``current``. It is a plain **monotonic integer**,
/// not semver — the only comparison anyone performs is
/// `appVersion >= scenarioRequirement`, so ordinal semantics are all that is
/// needed.
///
/// Engine is the correct home because bumping it is coupled to engine feature
/// additions (a new phase handler under `Engine/Phases/`, a new
/// `ScoreCalcLogic` under `Engine/ScoringLogic/`). The App layer reads the
/// constant via ``isCompatible(phases:minEngineVersion:)`` to drive the
/// Browse-tab grey-out gate. No dependency-rule violation: App→Engine and
/// App→Models are both allowed, and the predicate reads only Models
/// (`PhaseType.allCases`).
///
/// ## Bump policy
///
/// See ADR-020 §4 for the full bump policy. In short: **bump** when adding a
/// new `PhaseType` case, a new value of any by-name-parsed enum
/// (`ScoreCalcLogic` / `AssignTarget` / `PairingStrategy` / a new
/// `conditional` `if:` token), a new required property, a new top-level scalar
/// key, or any change to the semantics of an existing phase/property such that
/// an old app produces a *different* simulation. **Do not** bump for a truly
/// inert additive-optional string swept harmlessly into `extraData`.
nonisolated public enum EngineSchemaVersion {
  /// The current build's engine capability version. Baseline is `1`
  /// (set before the first App Store release, ADR-020 §5).
  public static let current: Int = 1

  /// Whether a gallery scenario described by its index metadata can be
  /// executed by this build's engine (ADR-020 D2 + D3).
  ///
  /// Two gates, combined with AND (a scenario is compatible only if it passes
  /// **both**):
  ///
  /// - **D2 — capability-derived (automatic).** Every phase kind in `phases`
  ///   must be known to this build (`PhaseType.allCases`). This is drift-proof
  ///   on the client side: `PhaseType.allCases` is the build's real capability
  ///   set, not a hand-maintained list. `phases` is expected to be the
  ///   *fully-flattened* phase-kind set including `conditional` branch
  ///   sub-phases (D2a).
  /// - **D3 — declared escape hatch.** The scenario's `min_engine_version` must
  ///   not exceed ``current``. This covers breaking changes invisible to D2's
  ///   phase-name check (a new by-name-parsed enum value, a new required
  ///   property, or a semantics-only change on a byte-identical YAML).
  ///
  /// Both inputs are decoded **leniently** (absent → `nil`). A `nil` `phases`
  /// means "capability cannot be determined from the index" → D2 defers
  /// (treated as unconstrained), relying on D3 and the parse-throw backstop
  /// (D5). A `nil` `minEngineVersion` means "unconstrained" (`0`).
  ///
  /// - Parameters:
  ///   - phases: The scenario's flattened phase-kind raw values from the
  ///     gallery index (`GalleryScenario.phases`), or `nil` when absent.
  ///   - minEngineVersion: The scenario's declared minimum engine version
  ///     (`GalleryScenario.min_engine_version`), or `nil` when absent.
  /// - Returns: `true` when this build can execute the scenario.
  public static func isCompatible(phases: [String]?, minEngineVersion: Int?) -> Bool {
    passesPhaseGate(phases) && passesVersionGate(minEngineVersion)
  }

  /// D2: every listed phase kind is known to this build. `nil`/empty → pass
  /// (unconstrained — see ``isCompatible(phases:minEngineVersion:)``).
  private static func passesPhaseGate(_ phases: [String]?) -> Bool {
    guard let phases else { return true }
    let known = Set(PhaseType.allCases.map(\.rawValue))
    return phases.allSatisfy(known.contains)
  }

  /// D3: the declared requirement does not exceed the current version.
  /// `nil` → `0` → pass.
  private static func passesVersionGate(_ minEngineVersion: Int?) -> Bool {
    (minEngineVersion ?? 0) <= current
  }
}
