import Foundation

/// Pure decision logic for the declaration/action contradiction badge (#916).
///
/// The ViewModel (live) and `ResultDetailTimelineBuilder` (Past Results) own
/// data assembly; this enum owns the single decision: did an agent's public
/// `declared_intent` get contradicted by *all* of its choose actions that
/// round? Kept `nonisolated` and dependency-free so it unit-tests off the
/// MainActor without rendering a View (ADR-009 / `.claude/rules/view-testing.md`).
///
/// Precision-first rules, fixed by the #916 PR1 harness validation:
/// - The declaration must be a clean match of one of the choose phase's
///   `options` — `unclear` (the sanctioned hedge) and free-form values never
///   badge.
/// - Every action must be a clean option match, and every one must differ
///   from the declaration. A partial split (betrayed one neighbour,
///   cooperated with the other) is opponent-conditioned strategy, not a
///   provable lie — no badge.
/// - Raw parsed actions are compared, not `ChooseHandler.validateAction`
///   output: validation coerces any unparseable action to `options[0]`,
///   which could manufacture a phantom contradiction. A dirty raw action
///   therefore disqualifies the whole round instead.
nonisolated enum ContradictionDetectionLogic {

  /// The reserved speak-phase output field carrying an agent's public stance
  /// (#916). Presence of this field is what opts a scenario into detection —
  /// no scenario-id keying.
  static let declaredIntentField = "declared_intent"

  /// The option vocabulary declarations are checked against: the first
  /// choose phase carrying options, searched through depth-1 conditional
  /// branches (the engine caps conditional nesting at depth 1, mirroring
  /// `ViewerPredictionLogic.flattened`). Scenarios with several differently
  /// -optioned choose phases per round are out of scope until one exists.
  static func chooseOptions(in phases: [Phase]) -> [String] {
    let all = phases.flatMap { phase in
      [phase] + (phase.thenPhases ?? []) + (phase.elsePhases ?? [])
    }
    return all.first { $0.type == .choose && !($0.options ?? []).isEmpty }?.options ?? []
  }

  /// Whether `declared` (a speak-phase `declared_intent` value) is
  /// contradicted by every entry in `actions` (the same agent's raw parsed
  /// choose actions from the same round), given the choose phase's `options`.
  static func isContradiction(
    declared: String?, actions: [String], options: [String]
  ) -> Bool {
    let normalizedOptions = options.map(normalize)
    guard let declared,
      case let declaredOption = normalize(declared),
      normalizedOptions.contains(declaredOption),
      !actions.isEmpty
    else { return false }

    return actions.allSatisfy { action in
      let actionOption = normalize(action)
      return normalizedOptions.contains(actionOption) && actionOption != declaredOption
    }
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
