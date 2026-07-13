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
  // relationship_update config (#910). YAML-only for v1 (no editing UI in
  // `PhaseEditorSheet`), but modelled here so a visual→YAML round-trip
  // preserves them instead of dropping them on re-serialization.
  var voteAgainst: Int?
  var actionDeltas: [String: Int]
  // Per-phase statement brevity override (#881). YAML-only for v1 (no editing
  // UI in `PhaseEditorSheet`), but modelled here so a visual→YAML round-trip
  // preserves it instead of dropping it on re-serialization.
  var maxSentences: Int?
  // event_inject draw-without-replacement opt-in (#1006). YAML-only for v1 (no
  // editing UI), modelled here so the visual→YAML round-trip preserves it.
  // `Bool` (not `Bool?`) mirrors `excludeSelf`: false and nil are semantically
  // identical, and `toPhase()` collapses false back to nil.
  var noRepeat: Bool
  // narrate voice descriptor (#909). YAML-only for v1 (no editing UI in
  // `PhaseEditorSheet`), modelled here so the visual→YAML round-trip preserves
  // it. `String` (not `String?`) mirrors `eventVariable`/`template`: empty and
  // nil are semantically identical, and `toPhase()` collapses empty back to nil.
  var narrator: String

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
    eventVariable: String = "",
    voteAgainst: Int? = nil,
    actionDeltas: [String: Int] = [:],
    maxSentences: Int? = nil,
    noRepeat: Bool = false,
    narrator: String = ""
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
    self.voteAgainst = voteAgainst
    self.actionDeltas = actionDeltas
    self.maxSentences = maxSentences
    self.noRepeat = noRepeat
    self.narrator = narrator
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
    self.voteAgainst = phase.voteAgainst
    self.actionDeltas = phase.actionDeltas ?? [:]
    self.maxSentences = phase.maxSentences
    self.noRepeat = phase.noRepeat ?? false
    self.narrator = phase.narrator ?? ""
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

  /// Reconciles `outputFields` to the canonical schema for the current
  /// `type`, so the visual editor defaults authors onto the
  /// ``ScenarioConventions`` convention — a phase no longer silently ships
  /// without its `inner_thought` thought bubble (the #799 authoring gap).
  ///
  /// This is an editor **default**, not a validation requirement:
  /// `inner_thought` stays optional by design (#760), and an author may still
  /// delete a seeded field afterwards.
  ///
  /// Pass `oldType` = the phase type before this change (`nil` when seeding a
  /// brand-new phase). Behavior:
  /// - Adds the current type's canonical primary + thought field if absent.
  /// - Removes a field only when it was `oldType`'s canonical primary/thought
  ///   **and** is not canonical for the new type — so `speak→vote` drops
  ///   `statement`/`inner_thought` and adds `vote`/`reason`, while
  ///   `speak→choose` keeps the shared `inner_thought`.
  /// - Preserves every non-canonical (author-added) field. Removed canonical
  ///   keys carry only the `"string"` type-hint value, never author content,
  ///   so the swap discards nothing meaningful.
  /// - Idempotent: re-applying the same type is a no-op.
  /// - Code phases (``ScenarioConventions`` returns `nil`) add nothing and, on
  ///   switching in, drop the prior LLM type's canonical fields.
  mutating func reconcileCanonicalOutputFields(from oldType: PhaseType?) {
    let newCanonical = canonicalFieldNames(for: type)
    if let oldType {
      // Drop the previous type's canonical fields that no longer apply.
      for key in canonicalFieldNames(for: oldType) where !newCanonical.contains(key) {
        outputFields.removeValue(forKey: key)
      }
    }
    // Seed the current type's canonical fields, leaving custom fields intact.
    for field in newCanonical where outputFields[field] == nil {
      outputFields[field] = "string"
    }
  }

  /// Clears a `max_sentences` override when the current `type` no longer emits
  /// an LLM statement (#881). Called on the same `.onChange(of: type)` event as
  /// ``reconcileCanonicalOutputFields(from:)`` so that switching an LLM phase
  /// (with an override set) to a code / control phase does not leave a hidden,
  /// no-longer-editable value behind — such a value would round-trip into the
  /// code phase and silently trip the R18 `max-sentences-no-op` linter (a
  /// warning that never blocks, ADR-024), defeating the editor's LLM-only
  /// display gate. Idempotent: a no-op when `type` still requires LLM or the
  /// override is already nil.
  mutating func reconcileMaxSentences() {
    if !type.requiresLLM {
      maxSentences = nil
    }
  }

  /// The canonical primary + thought output field names for `type`
  /// (empty for code phases that emit no LLM output).
  private func canonicalFieldNames(for type: PhaseType) -> [String] {
    [
      ScenarioConventions.primaryField(for: type),
      ScenarioConventions.thoughtField(for: type)
    ].compactMap { $0 }
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
      eventVariable: eventVariable.isEmpty ? nil : eventVariable,
      voteAgainst: voteAgainst,
      actionDeltas: actionDeltas.isEmpty ? nil : actionDeltas,
      maxSentences: maxSentences,
      noRepeat: noRepeat ? true : nil,
      narrator: narrator.isEmpty ? nil : narrator
    )
  }
}
