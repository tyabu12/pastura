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
  var probability: Double?
  var eventVariable: String

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
    elsePhases: [EditablePhase] = [],
    probability: Double? = nil,
    eventVariable: String = ""
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
    self.probability = probability
    self.eventVariable = eventVariable
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
    self.probability = phase.probability
    self.eventVariable = phase.eventVariable ?? ""
  }

  /// Identifies which branch of a conditional phase to target.
  enum Branch: String, Sendable, CaseIterable {
    case then
    case `else`
  }

  /// Moves the sub-phase with the given `id` from whichever branch it
  /// currently lives in to the end of `destination`. Always tail-appends
  /// by design — within-branch position adjustment uses SwiftUI's
  /// `.onMove` in the editor. No-op when:
  /// - the id isn't found in either branch (e.g., deep nested sub-phase)
  /// - the id is already in `destination` (moving to the branch it
  ///   currently lives in)
  mutating func moveSubPhase(id sourceId: UUID, to destination: Branch) {
    // Shallow scan only — depth-1 is enforced at the editor layer.
    if let index = thenPhases.firstIndex(where: { $0.id == sourceId }) {
      guard destination == .else else { return }
      let moved = thenPhases.remove(at: index)
      elsePhases.append(moved)
    } else if let index = elsePhases.firstIndex(where: { $0.id == sourceId }) {
      guard destination == .then else { return }
      let moved = elsePhases.remove(at: index)
      thenPhases.append(moved)
    }
    // If not found in either branch, no-op.
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
      elsePhases: elsePhases.isEmpty ? nil : elsePhases.map { $0.toPhase() },
      probability: probability,
      eventVariable: eventVariable.isEmpty ? nil : eventVariable
    )
  }
}
