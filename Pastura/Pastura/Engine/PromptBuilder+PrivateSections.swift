import Foundation

// Sibling-file split of `PromptBuilder` (file_length cap). `nonisolated` on the
// extension is load-bearing under default-MainActor isolation (swift-isolation.md
// Pattern 3): the base type is `nonisolated`, and `buildSystemPrompt` calls this
// from a nonisolated context.
nonisolated extension PromptBuilder {

  /// Appends the persona's static hidden agenda (`Persona/secret`, #914) to
  /// `sections`, when it has one.
  ///
  /// Unlike the dynamic per-round sections below, this is **author-time static
  /// text** that belongs to the persona itself — so it is placed right after the
  /// character section and before any per-round state.
  ///
  /// The anti-leak guidance lives inside the section (not `buildAnswerRules`) so
  /// it is present exactly when a secret is. Its scope is deliberately
  /// **channel-based**: the prohibition covers only what other agents can hear
  /// (`statement`), and `inner_thought` is explicitly licensed — the harness A/B
  /// found a blanket "don't say it" wording also suppressed the inner monologue,
  /// which is the dramatic-irony payoff surface the secret should reach. Phases
  /// with no `inner_thought` field degrade gracefully (the license line is inert).
  ///
  /// `whisper` was considered and is covered: its canonical field is also
  /// `statement`, so "anything the other participants can hear" forbids reveal
  /// there too. But note the two rules pull opposite ways on a 2B-class model —
  /// `whisperRule` tells the agent to be candid and strategic with its partner,
  /// while this one forbids naming the secret. Field-test a secret × whisper
  /// scenario before any preset ships both (#914 follow-up).
  ///
  /// The closing sentence is **declarative**, matching the ja literal's close and
  /// restoring the ja/en scope-parallel expectation the sibling rules in
  /// `PromptBuilder.swift` document. It was chosen by measurement (#1301), and
  /// what the measurement licenses is narrow. On **decisions** the sentence is
  /// inert: an imperative arm, this declarative arm, and a control with the
  /// sentence deleted all landed at the 50 % chance baseline, while a positive
  /// control carrying an explicit directive reached 100 % — so the flatness
  /// belongs to the sentence, not to the instrument. A blinded read of the inner
  /// monologue ranked the deleted-sentence control lowest, which is why the
  /// sentence stays at all; that arm separation is under-powered and supports
  /// only "declarative is not worse", never "declarative is better". Only the
  /// sentence's **mood** was measured — the clause before it was held constant
  /// across every arm and remains unmeasured.
  func appendSecretSection(to sections: inout [String], persona: Persona, language: String) {
    // Non-nil implies non-empty (every ingest path normalizes empty → nil).
    guard let secret = persona.secret else { return }
    let header = pickLanguage(
      language,
      ja: "## あなたの秘密（他の参加者は知りません）",
      en: "## Your Secret (the other participants do not know this)")
    let guidance = pickLanguage(
      language,
      ja:
        "この秘密は、他の参加者に聞こえる発言（statement）では決して明かしてはいけません。心の声（inner_thought）では率直に触れてかまいません。あなたの判断や態度はこの秘密に左右されます。",
      en:
        "Never reveal this secret in anything the other participants can hear (your statement). You may reference it freely in your inner_thought. It shapes your judgement and attitude."
    )
    sections.append("\(header)\n\(secret)\n\(guidance)")
  }

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
        ja: "## あなたの非公開メモ（他の参加者には見えません）",
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
