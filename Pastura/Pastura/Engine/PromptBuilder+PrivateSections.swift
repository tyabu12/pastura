import Foundation

// Sibling-file split of `PromptBuilder` (file_length cap). `nonisolated` on the
// extension is load-bearing under default-MainActor isolation (swift-isolation.md
// Pattern 3): the base type is `nonisolated`, and `buildSystemPrompt` calls this
// from a nonisolated context.
nonisolated extension PromptBuilder {

  /// Appends each agent's private self-knowledge sections to `sections`:
  /// the reflect note (`notes_<name>`, #907), the whisper channel
  /// (`whispers_<name>`, #908), and the relationship read
  /// (`relationships_<name>`, #910).
  ///
  /// Each is derived only for that agent and never enters the conversation log,
  /// so every header stresses its privacy. An absent or empty value renders no
  /// section (no empty header). Extracted from `buildSystemPrompt` to keep that
  /// function under the `function_body_length` cap.
  func appendPrivateSections(
    to sections: inout [String], persona: Persona, state: SimulationState, language: String
  ) {
    if let note = state.variables["notes_\(persona.name)"], !note.isEmpty {
      let header = pickLanguage(
        language,
        ja: "## あなたの内心メモ（他の参加者には見えません）",
        en: "## Your Private Notes (invisible to other participants)")
      sections.append("\(header)\n\(note)")
    }

    if let whispers = state.variables["whispers_\(persona.name)"], !whispers.isEmpty {
      let header = pickLanguage(
        language,
        ja: "## あなたの密談（密談相手以外には見えません）",
        en: "## Your Private Whispers (invisible to everyone except your whisper partner)")
      sections.append("\(header)\n\(whispers)")
    }

    if let relationships = state.variables["relationships_\(persona.name)"], !relationships.isEmpty {
      let header = pickLanguage(
        language,
        ja: "## あなたの人間関係（他の参加者には見えません）",
        en: "## Your Read on the Others (invisible to other participants)")
      sections.append("\(header)\n\(relationships)")
    }

    // Mood is placed LAST (#913): a transient emotional state carried from the
    // prior turn, positioned nearest the answer rules for recency, and (unlike
    // notes/whispers/relationships) surfaced in EVERY phase so the inertia
    // survives intervening vote/choose phases up to the next speak.
    if let mood = state.variables["mood_\(persona.name)"], !mood.isEmpty {
      let header = pickLanguage(
        language,
        ja: "## あなたの今の気分",
        en: "## Your Current Mood")
      sections.append("\(header)\n\(mood)")
    }
  }
}
