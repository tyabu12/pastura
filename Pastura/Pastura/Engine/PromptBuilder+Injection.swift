import Foundation

// Sibling-file split of `PromptBuilder` (file_length cap). `nonisolated` on the
// extension is load-bearing under default-MainActor isolation (swift-isolation.md
// Pattern 3): the base type is `nonisolated`, and the LLM handlers call these
// from a nonisolated context.
//
// Groups the reserved-namespace `{token}` injection helpers — each reads a
// per-persona `<prefix>_<name>` key from the variables copy and surfaces it to
// only the current speaker (system-prompt section + a public `{token}`) — plus
// the mood capture side (#913). The matching system-prompt *sections* live in
// `PromptBuilder+PrivateSections.swift`; the mood answer-rule in the main file.
nonisolated extension PromptBuilder {

  /// Injects the current speaker's `assign`-phase value under the canonical
  /// `{assigned}` key and its backward-compat alias `{assigned_word}`.
  ///
  /// `AssignHandler` stores each agent's value under a per-persona key
  /// `assigned_<name>`; this reads that back for the speaker so per-persona
  /// prompt templates resolve (#890 — before this, `{assigned_word}` leaked
  /// literally and Word Wolf's secret-word mechanic never worked).
  ///
  /// Missing assignment resolves to empty string (not a literal placeholder),
  /// matching `EventInjectHandler`'s miss posture for assign-less scenarios.
  ///
  /// - Note: reads from the passed `variables` copy (seeded from
  ///   `state.variables`), so a persona literally named `word` would produce
  ///   key `assigned_word` that collides with this alias — the alias then
  ///   reflects the current speaker's value, not that persona's assignment.
  ///   Contrived and absent from all bundled presets; the `assigned_` prefix
  ///   is effectively a reserved namespace.
  func injectAssigned(into variables: inout [String: String], personaName: String) {
    let mine = variables["assigned_\(personaName)"] ?? ""
    variables["assigned"] = mine
    variables["assigned_word"] = mine
  }

  /// Injects the current speaker's `reflect`-phase memo under the `{my_notes}`
  /// key.
  ///
  /// ``ReflectHandler`` stores each agent's private note under a per-persona
  /// key `notes_<name>` (#907); this reads that back for the speaker so custom
  /// user-prompt templates can reference `{my_notes}`. The `notes_` prefix is a
  /// reserved namespace, mirroring `assigned_` (see ``injectAssigned(into:personaName:)``).
  ///
  /// Missing note resolves to empty string (not a literal placeholder), matching
  /// `injectAssigned`'s miss posture.
  ///
  /// - Note: the privacy guarantee covers the conversation-log, system-prompt,
  ///   and `{my_notes}` paths. Raw `notes_<other>` keys remain resolvable by a
  ///   template that hand-references them (`{notes_Bob}`) — same exposure as
  ///   the `assigned_` namespace, accepted for pattern consistency.
  func injectNotes(into variables: inout [String: String], personaName: String) {
    variables["my_notes"] = variables["notes_\(personaName)"] ?? ""
  }

  /// Injects the current speaker's `whisper`-phase channel under the
  /// `{my_whispers}` key.
  ///
  /// ``WhisperHandler`` stores each participant's private view of their pair's
  /// exchange under a per-persona key `whispers_<name>` (#908); this reads that
  /// back for the speaker so custom user-prompt templates can reference
  /// `{my_whispers}`. The `whispers_` prefix is a reserved namespace, mirroring
  /// `notes_` (see ``injectNotes(into:personaName:)``).
  ///
  /// Missing channel resolves to empty string (not a literal placeholder),
  /// matching `injectNotes`'s miss posture.
  ///
  /// - Note: the privacy guarantee covers the conversation-log, system-prompt,
  ///   and `{my_whispers}` paths. Raw `whispers_<other>` keys remain resolvable
  ///   by a template that hand-references them (`{whispers_Bob}`) — same
  ///   accepted residual exposure as the `notes_<name>` namespace, kept for
  ///   pattern consistency.
  func injectWhispers(into variables: inout [String: String], personaName: String) {
    variables["my_whispers"] = variables["whispers_\(personaName)"] ?? ""
  }

  /// Injects the current speaker's `relationship_update` affinity summary under
  /// the `{relationships}` key.
  ///
  /// ``RelationshipUpdateHandler`` stores each agent's prose read on the others
  /// under a per-persona key `relationships_<name>` (#910); this reads that back
  /// for the speaker so custom user-prompt templates can reference
  /// `{relationships}`. The `relationships_` prefix is a reserved namespace,
  /// mirroring `notes_` (see ``injectNotes(into:personaName:)``). Missing summary
  /// resolves to empty string (not a literal placeholder), matching
  /// `injectNotes`'s miss posture.
  func injectRelationships(into variables: inout [String: String], personaName: String) {
    variables["relationships"] = variables["relationships_\(personaName)"] ?? ""
  }

  /// Injects the current speaker's carried-over `mood` under the `{my_mood}`
  /// key.
  ///
  /// A phase that opts into a `mood` output field (#913) has its non-empty
  /// value captured by ``captureMood(from:into:personaName:)`` under the
  /// per-persona key `mood_<name>`; this reads that back for the speaker so
  /// custom user-prompt templates can reference `{my_mood}`. The `mood_` prefix
  /// is a reserved namespace, mirroring `notes_` (see
  /// ``injectNotes(into:personaName:)``). Missing mood resolves to empty string
  /// (not a literal placeholder), matching `injectNotes`'s miss posture — so a
  /// scenario that never opts in, or the first round before any mood is set,
  /// renders no mood text.
  ///
  /// - Note: unlike `notes_`/`whispers_`, an agent never sees another agent's
  ///   mood — mood is self-referential emotional inertia, not shared
  ///   information, so there is no cross-agent leak surface here.
  func injectMood(into variables: inout [String: String], personaName: String) {
    variables["my_mood"] = variables["mood_\(personaName)"] ?? ""
  }

  /// Persists a turn's `mood` output field under the reserved per-persona key
  /// `mood_<name>` so it carries into the same agent's next prompt (#913).
  ///
  /// Only writes a **non-empty** mood: a failed/empty inference (`LLMCaller`
  /// returns `""` after exhausting the empty-field retry budget) must not erase
  /// the agent's mood from a previous turn — the same non-empty guard
  /// ``ReflectHandler`` applies to its note. last-write-wins, so a `whisper`
  /// phase's `sub_rounds` keep only the latest exchange's mood. A phase whose
  /// schema does not declare `mood` never produces the key (grammar-constrained
  /// decoding), so this is a no-op there — called from every LLM handler for
  /// symmetry and forward-compatibility.
  func captureMood(
    from output: TurnOutput, into variables: inout [String: String], personaName: String
  ) {
    let mood = output.fields["mood"] ?? ""
    if !mood.isEmpty {
      variables["mood_\(personaName)"] = mood
    }
  }
}
