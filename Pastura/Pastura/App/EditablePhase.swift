import Foundation

/// Mutable phase for visual editing.
///
/// Separates editing state from the immutable ``Phase`` domain model.
/// Exposes all phase fields; type-dependent visibility is handled by the UI.
///
/// Conditional-specific fields (`condition`, `thenPhases`, `elsePhases`)
/// hold nested `EditablePhase` values so the editor can recursively render
/// sub-phase blocks. Depth-1 is enforced at the editor layer by filtering
/// `.conditional` out of the type picker when `PhaseEditorSheet` is opened
/// for a nested phase.
struct EditablePhase: Identifiable, Sendable {
  /// Which branch of a `conditional` phase a sub-phase belongs to.
  enum Branch: String, Codable, Sendable, CaseIterable {
    case then
    case `else`
  }
  let id = UUID()
  var type: PhaseType
  var prompt: String
  var outputFields: [String: String]
  var options: [String]
  var pairing: PairingStrategy?
  var logic: ScoreCalcLogic?
  var template: String
  var source: String
  var target: String
  var excludeSelf: Bool
  var subRounds: Int?
  var condition: String
  var thenPhases: [EditablePhase]
  var elsePhases: [EditablePhase]

  // swiftlint:disable:next function_default_parameter_at_end
  init(
    type: PhaseType = .speakAll,
    prompt: String = "",
    outputFields: [String: String] = [:],
    options: [String] = [],
    pairing: PairingStrategy? = nil,
    logic: ScoreCalcLogic? = nil,
    template: String = "",
    source: String = "",
    target: String = "",
    excludeSelf: Bool = false,
    subRounds: Int? = nil,
    condition: String = "",
    thenPhases: [EditablePhase] = [],
    elsePhases: [EditablePhase] = []
  ) {
    self.type = type
    self.prompt = prompt
    self.outputFields = outputFields
    self.options = options
    self.pairing = pairing
    self.logic = logic
    self.template = template
    self.source = source
    self.target = target
    self.excludeSelf = excludeSelf
    self.subRounds = subRounds
    self.condition = condition
    self.thenPhases = thenPhases
    self.elsePhases = elsePhases
  }

  init(from phase: Phase) {
    self.type = phase.type
    self.prompt = phase.prompt ?? ""
    self.outputFields = phase.outputSchema ?? [:]
    self.options = phase.options ?? []
    self.pairing = phase.pairing
    self.logic = phase.logic
    self.template = phase.template ?? ""
    self.source = phase.source ?? ""
    self.target = phase.target?.rawValue ?? ""
    self.excludeSelf = phase.excludeSelf ?? false
    self.subRounds = phase.subRounds
    self.condition = phase.condition ?? ""
    self.thenPhases = phase.thenPhases?.map { EditablePhase(from: $0) } ?? []
    self.elsePhases = phase.elsePhases?.map { EditablePhase(from: $0) } ?? []
  }

  /// Moves a sub-phase identified by `id` into `branch` at `destinationIndex`.
  ///
  /// **Destination-index convention:** `destinationIndex` is the *final* index
  /// in the destination array after the move — i.e. where the item ends up
  /// after insertion. This differs from SwiftUI's `.onMove(fromOffsets:toOffset:)`
  /// which uses a pre-removal index.
  ///
  /// **Clamp behaviour:**
  /// - Cross-branch: clamp to `destinationBranch.count` (before insert).
  /// - Within-branch: after the item is removed the array shrinks by one;
  ///   clamp to `count - 1` (post-removal length).
  /// - If `destinationIndex < 0`, clamp to `0`.
  ///
  /// **Unknown UUID:** no-op — no mutation, no crash.
  mutating func moveSubPhase(id sourceId: UUID, to branch: Branch, at destinationIndex: Int) {
    // Locate the item in either branch.
    let inThen = thenPhases.firstIndex(where: { $0.id == sourceId })
    let inElse = elsePhases.firstIndex(where: { $0.id == sourceId })

    guard let sourceIndex = inThen ?? inElse else { return }
    let sourceBranch: Branch = inThen != nil ? .then : .else

    if sourceBranch == branch {
      // Within-branch move: remove first, then insert at clamped destination.
      var array = sourceBranch == .then ? thenPhases : elsePhases
      let item = array.remove(at: sourceIndex)
      // After removal the array is one shorter; clamp into the reduced range.
      let clampedDest = Swift.max(0, Swift.min(destinationIndex, array.count))
      array.insert(item, at: clampedDest)
      if sourceBranch == .then {
        thenPhases = array
      } else {
        elsePhases = array
      }
    } else {
      // Cross-branch move.
      var source = sourceBranch == .then ? thenPhases : elsePhases
      var dest = branch == .then ? thenPhases : elsePhases
      let item = source.remove(at: sourceIndex)
      let clampedDest = Swift.max(0, Swift.min(destinationIndex, dest.count))
      dest.insert(item, at: clampedDest)
      if sourceBranch == .then {
        thenPhases = source
        elsePhases = dest
      } else {
        elsePhases = source
        thenPhases = dest
      }
    }
  }

  func toPhase() -> Phase {
    let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
    return Phase(
      type: type,
      prompt: prompt.isEmpty ? nil : prompt,
      outputSchema: outputFields.isEmpty ? nil : outputFields,
      options: options.isEmpty ? nil : options,
      pairing: pairing,
      logic: logic,
      template: template.isEmpty ? nil : template,
      source: source.isEmpty ? nil : source,
      // Invalid strings silently nil here — the editor's `validate()` surfaces
      // a user-visible error before this point so typos don't reach the engine.
      target: trimmedTarget.isEmpty ? nil : AssignTarget(rawValue: trimmedTarget),
      excludeSelf: excludeSelf ? true : nil,
      subRounds: subRounds,
      condition: trimmedCondition.isEmpty ? nil : trimmedCondition,
      thenPhases: thenPhases.isEmpty ? nil : thenPhases.map { $0.toPhase() },
      elsePhases: elsePhases.isEmpty ? nil : elsePhases.map { $0.toPhase() }
    )
  }
}

extension Array where Element == EditablePhase {
  /// Moves the phase with `id` to `destinationIndex` within this array.
  ///
  /// **Destination-index convention:** `destinationIndex` is the *final* index
  /// after the move — where the item ends up after insertion. After removal the
  /// array shrinks by one; `destinationIndex` is clamped to the post-removal
  /// count (i.e. the last valid insertion index). If `destinationIndex < 0`,
  /// clamp to `0`.
  ///
  /// **Unknown UUID:** no-op — no mutation, no crash.
  mutating func movePhase(id sourceId: UUID, to destinationIndex: Int) {
    guard let sourceIndex = firstIndex(where: { $0.id == sourceId }) else { return }
    let item = remove(at: sourceIndex)
    let clampedDest = Swift.max(0, Swift.min(destinationIndex, count))
    insert(item, at: clampedDest)
  }
}
