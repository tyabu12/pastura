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
  /// `PromptBuilder.swift` document. That convention — **not** a behavioural gain
  /// — is what settled it (#1301); the A/B licenses far less than it may appear.
  ///
  /// On **decisions**, in **en**, on Gemma 4 E2B (Q4_K_M), on a purpose-built
  /// probe whose personas carried bare `secret:` text, the sentence is inert: an
  /// imperative arm, this declarative arm, and a control with the sentence
  /// deleted all sat on the 50 % chance baseline (imperative 13/25 · declarative
  /// 12/25 · control 6/12 of the vote turns that named a person; ~31 % named a
  /// proposal instead and were dropped, evenly across arms, so the baseline is
  /// over that retained subset). A positive control reached 100 % (6/6, one run),
  /// but its directive sat in the scenario's `secret:` text — that shows the
  /// *metric* is movable, which is not the same as text in *this* slot being able
  /// to move it. The **ja** close was never an arm and is entirely unmeasured.
  ///
  /// The sentence is kept as the **status quo**: no arm of the pre-registered
  /// rule could have deleted it. A blinded inner-monologue read did rank the
  /// deleted-sentence control lowest (declarative 12/12 · imperative 10/12 ·
  /// control 8/12), but at n=12/arm the scorer declined to reject a common
  /// distribution, so the pre-registered rule gave that ordering no role in the
  /// decision; it supports "declarative is not worse", never "better".
  ///
  /// Only the closing sentence's **formulation** varied — mood, segmentation and
  /// word choice moved together, so none of the three is separately attributable.
  /// The clause before it was held constant across every arm.
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
