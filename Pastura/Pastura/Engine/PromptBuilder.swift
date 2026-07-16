import Foundation

/// Builds LLM prompts for simulation phases.
///
/// Handles template variable expansion, system prompt construction with persona
/// and scenario context, and conversation log formatting for prompt injection.
nonisolated struct PromptBuilder: Sendable {

  // MARK: - Template Expansion

  /// Replaces `{key}` placeholders in a template with values from the variables dictionary.
  ///
  /// Unknown placeholders (no matching key) are left unchanged.
  func expandTemplate(_ template: String, variables: [String: String]) -> String {
    var result = template
    for (key, value) in variables {
      result = result.replacingOccurrences(of: "{\(key)}", with: value)
    }
    return result
  }

  // MARK: - Scoreboard

  /// Serializes a score dictionary into a compact JSON-like string for template injection.
  ///
  /// Keys are sorted alphabetically so output is deterministic regardless of dictionary order.
  func formatScoreboard(_ scores: [String: Int]) -> String {
    let pairs = scores.sorted { $0.key < $1.key }
      .map { "\"\($0.key)\": \($0.value)" }
    return "{\(pairs.joined(separator: ", "))}"
  }

  // MARK: - Conversation Log

  /// Serializes structured conversation entries into a plain text string for prompt injection.
  ///
  /// Empty-log placeholder is `"（まだなし）"` (ja) / `"(none yet)"` (en),
  /// chosen via the effective Engine language (callers pass
  /// `scenario.engineLanguage`, ADR-010 D5 / D6 row 1). ADR-010 D7
  /// Translation Table.
  ///
  /// - Parameter window: Optional cap (`scenario.logWindow`, #907). When
  ///   non-nil, only the last `window` entries are formatted — a prompt-side
  ///   trim; the full log is untouched in persistence. `nil` keeps every entry.
  ///   For any `window ≥ 1` (the validator's floor) the trimmed slice is
  ///   non-empty whenever `entries` is, so the empty-log placeholder still only
  ///   fires on a genuinely empty log.
  func formatConversationLog(
    _ entries: [ConversationEntry], language: String, window: Int? = nil
  ) -> String {
    if entries.isEmpty {
      return pickLanguage(language, ja: "（まだなし）", en: "(none yet)")
    }
    let windowed = window.map { Array(entries.suffix($0)) } ?? entries
    return windowed.map { "  \($0.agentName): \($0.content)" }.joined(separator: "\n")
  }

  // MARK: - Main Field Detection

  /// Returns the canonical primary output field name for a phase, used as
  /// the dictionary key when populating the conversation log from
  /// ``TurnOutput/fields``.
  ///
  /// Defers to ``ScenarioConventions/primaryField(for:)`` for the canonical
  /// per-phase field; falls back to `"statement"` for code phases (which
  /// don't normally reach this method since the speak handlers are the
  /// only callers).
  func getMainField(phase: Phase) -> String {
    ScenarioConventions.primaryField(for: phase.type) ?? "statement"
  }

  // MARK: - System Prompt

  /// Builds the system prompt for an agent's LLM call.
  ///
  /// Includes: scenario context, persona description, answer rules
  /// (target-language output, no empty fields, single-line JSON), output
  /// format specification, and phase-specific constraints (options for
  /// choose, candidate list for vote). All user-facing strings dispatch
  /// on `scenario.engineLanguage` per ADR-010 D7 (the override-aware
  /// resolver defined in D5 / D6 row 1).
  func buildSystemPrompt(
    scenario: Scenario,
    persona: Persona,
    phase: Phase,
    state: SimulationState
  ) -> String {
    var sections: [String] = []
    let language = scenario.engineLanguage

    // Header
    sections.append(
      pickLanguage(
        language,
        ja: "あなたはシミュレーションの参加者です。キャラクターになりきってください。",
        en: "You are a participant in a simulation. Stay in character."))

    // Scenario context
    let scenarioHeader = pickLanguage(language, ja: "## シナリオ", en: "## Scenario")
    sections.append(
      """
      \(scenarioHeader)
      \(scenario.context)
      """)

    // Persona
    let personaHeader = pickLanguage(
      language, ja: "## あなたのキャラクター", en: "## Your Character")
    let nameLabel = pickLanguage(language, ja: "名前", en: "Name")
    sections.append(
      """
      \(personaHeader)
      \(nameLabel): \(persona.name)
      \(persona.description)
      """)

    // Static hidden agenda (#914) — author-time persona text, so it precedes the
    // per-round state sections below.
    appendSecretSection(to: &sections, persona: persona, language: language)

    // Private self-knowledge sections (reflect note #907, whisper channel #908,
    // relationship read #910) — each surfaced to only that agent. Extracted to
    // `PromptBuilder+PrivateSections.swift` to keep this function under the
    // body-length cap.
    appendPrivateSections(to: &sections, persona: persona, state: state, language: language)

    sections.append(
      buildAnswerRules(scenario: scenario, persona: persona, phase: phase, state: state))

    if let formatSection = formatOutputSchema(OutputSchema.from(phase: phase), language: language) {
      sections.append(formatSection)
    }

    return sections.joined(separator: "\n\n")
  }

  /// The global default statement brevity cap (sentences) applied when a
  /// phase declares no `max_sentences` override (#881, #877).
  static let defaultStatementMaxSentences = 3

  /// Builds the `## 回答ルール / ## Response Rules` block + phase-specific
  /// constraints (choose options, vote candidate list). Extracted from
  /// `buildSystemPrompt` so the Translation Table per-site dispatch fits
  /// inside the function_body_length cap.
  ///
  /// The two trailing "syntax error" / "single object only" rules in the
  /// base block were added in #194 PR#a Item 3 (A3 prompt hardening) to
  /// reduce Hyp A (JSON parse retry) frequency by reinforcing structural
  /// validity at the source on Gemma 4 E2B Q4_K_M.
  ///
  /// The brevity rule (#877) is a soft cap on the primary statement field
  /// only — inner_thought is intentionally unconstrained. Wording is
  /// harness-A/B-tuned; keep ja/en scope-parallel when editing.
  ///
  /// The sentence count is per-phase overridable via `phase.maxSentences`
  /// (#881), defaulting to ``defaultStatementMaxSentences``. The override
  /// **replaces** the number in the single brevity bullet (never appends a
  /// second, contradictory cap); an absent override renders byte-identical to
  /// the shipped #877 wording. Empirically a ja lever — see
  /// ``Phase/maxSentences``.
  private func buildAnswerRules(
    scenario: Scenario,
    persona: Persona,
    phase: Phase,
    state: SimulationState
  ) -> String {
    let language = scenario.engineLanguage
    // Per-phase statement brevity cap (#881): phase override, else the global
    // default. The number is interpolated into the single brevity bullet
    // (REPLACE) so the default (3) renders byte-identical to the #877 wording
    // and no second, contradictory cap is ever appended.
    let maxSentences = phase.maxSentences ?? Self.defaultStatementMaxSentences
    let sentenceNoun = maxSentences == 1 ? "sentence" : "sentences"
    var rules = pickLanguage(
      language,
      ja: """
        ## 回答ルール（厳守）
        - 必ず日本語で回答すること
        - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
        - 発言（statement などの本文フィールド）は\(maxSentences)文以内で簡潔に書くこと（長い独白は禁止）
        - JSONは必ず1行で書くこと（改行を入れない）
        - JSON以外のテキストやコードブロック(```)は書かないこと
        - JSONに構文エラーがあると失敗扱いになる（カッコ・引用符・カンマを正しく閉じること）
        - {で始まり}で終わる単一オブジェクトのみ出力し、前後にテキストを付けないこと
        """,
      en: """
        ## Response Rules (strict)
        - Respond in English only.
        - Every field must contain a sentence (no empty "..." values).
        - Keep your statement (the main text field) concise: at most \(maxSentences) \(sentenceNoun), no long monologues.
        - The JSON output must be a single line (no newlines).
        - Do not include any text or code fences (```) outside the JSON.
        - JSON syntax errors are treated as failure: close every bracket, quote, and comma correctly.
        - Output exactly one object starting with { and ending with }, with no surrounding text.
        """)

    // Turn-based speak_each gets the #911 address rule (see `addressRule`).
    if phase.type == .speakEach {
      rules += addressRule(language: language)
    }

    // Reflect notes get a tighter 2-sentence cap (see `reflectBrevityRule`).
    if phase.type == .reflect {
      rules += reflectBrevityRule(language: language)
    }

    // Whisper turns get partner-directed privacy guidance (see `whisperRule`).
    if phase.type == .whisper {
      rules += whisperRule(language: language)
    }

    if phase.type == .choose, let options = phase.options {
      let optionsList = options.joined(separator: ", ")
      rules += pickLanguage(
        language,
        ja: "\n- actionフィールドは必ず次のいずれかを書くこと: \(optionsList)",
        en: "\n- The action field must be one of: \(optionsList)")
    }

    if phase.type == .vote {
      rules += voteCandidateRule(scenario: scenario, persona: persona, phase: phase, state: state)
    }

    // Mood-opting phases (#913) get the mood-writing guidance. Gated on the
    // schema, not the phase type — any LLM phase can declare `mood`.
    if phase.outputSchemaKeys.contains("mood") {
      rules += moodRule(language: language)
    }

    return rules
  }

  /// The `vote` candidate-list constraint appended for vote phases only.
  /// Lists the valid vote targets (excluding self under `exclude_self` and
  /// any eliminated agent). Extracted from `buildAnswerRules` to keep that
  /// function under the `function_body_length` cap.
  private func voteCandidateRule(
    scenario: Scenario, persona: Persona, phase: Phase, state: SimulationState
  ) -> String {
    let excludeSelf = phase.excludeSelf ?? true
    let candidates = scenario.personas
      .map(\.name)
      .filter { name in
        if excludeSelf && name == persona.name { return false }
        if state.eliminated[name] == true { return false }
        return true
      }
    let candidatesList = candidates.joined(separator: ", ")
    return pickLanguage(
      scenario.engineLanguage,
      ja: "\n- voteフィールドは必ず次の名前のいずれかを正確に書くこと: \(candidatesList)",
      en: "\n- The vote field must be exactly one of these names: \(candidatesList)")
  }

  /// The #907 brevity rule appended for `reflect` phases only. Caps the private
  /// note at 2 sentences — same constraint family as the #877 statement brevity
  /// rule. Keep ja/en scope-parallel when editing.
  private func reflectBrevityRule(language: String) -> String {
    pickLanguage(
      language,
      ja: "\n- メモ（note）は2文以内で簡潔に書くこと（長文・箇条書きの羅列は禁止）",
      en: "\n- Keep your note to at most 2 sentences (no long paragraphs or bullet lists).")
  }

  /// The #913 mood-writing guidance, appended only for phases that opt into a
  /// `mood` output field (`buildAnswerRules` gates on the schema). A short-word
  /// cap plus an explicit "change naturally, don't force-maintain or abruptly
  /// reset" instruction is the primary lever against the two failure modes:
  /// echo-fixation (the same mood every turn) and unmotivated slashing (random
  /// flips unrelated to events). Keep ja/en scope-parallel; wording is
  /// harness-A/B-tunable. The reserved-namespace inject/capture side lives in
  /// `PromptBuilder+Injection.swift`.
  private func moodRule(language: String) -> String {
    pickLanguage(
      language,
      ja:
        "\n- moodには今の気分を短い言葉で書くこと（例: わくわく、苛立ち、不安）。気分は出来事に応じて自然に変化してよく、無理に維持も急変もしないこと",
      en:
        "\n- Write your current mood in the mood field as a short phrase (e.g. excited, irritated, uneasy). Let it shift naturally with what happens — neither forced to stay the same nor snapped to something unrelated."
    )
  }

  /// The #908 privacy guidance appended for `whisper` phases only. A whisper is
  /// a secret one-to-one exchange: nobody except the partner can hear it, so the
  /// agent should address the partner directly, stay candid/strategic, and keep
  /// it conversational. Keep ja/en scope-parallel when editing.
  private func whisperRule(language: String) -> String {
    pickLanguage(
      language,
      ja: "\n- これは密談相手ひとりだけへの秘密の耳打ちです（他の参加者には聞こえません）。相手に直接呼びかけ、本音で戦略的に、短い会話として話すこと",
      en:
        "\n- This is a private whisper to your one partner only (no one else can hear). Address them directly, be candid and strategic, and keep it conversational."
    )
  }

  /// The #911 address rule appended for turn-based `speak_each` phases only.
  ///
  /// speak_each otherwise produces parallel monologues (0 % cross-reference at
  /// baseline); a harness A/B on Gemma 4 E2B lifted word_wolf address-rate to
  /// ~0.27 (ja) / ~0.18 (en) with no agreement-formulae collapse. It is NOT
  /// appended for `speak_all`: the A/B showed it inert there (simultaneous
  /// broadcast framing dominates, e.g. prisoners' "全員に向けて宣言") and mildly
  /// harmful (parse failures + bokete boke-copying). The "反論でも疑問でもよい"
  /// clause blocks the agreement-formulae collapse mode. Keep ja/en
  /// scope-parallel; wording is harness-A/B-tuned.
  private func addressRule(language: String) -> String {
    pickLanguage(
      language,
      ja:
        "\n- これまでの会話に他の誰かの発言があれば、そのうち1人の発言に必ず触れてから自分の意見を述べること（同意でも反論でも疑問でもよい）。まだ誰も発言していなければ自由に話してよい",
      en:
        "\n- If anyone has spoken earlier in the conversation, refer to one of their statements before giving your own opinion (agreement, disagreement, or a question all count). If no one has spoken yet, speak freely."
    )
  }

  /// Render the `## 出力フォーマット（JSON）` / `## Output Format (JSON)`
  /// section + placeholder example line (#194 PR#a Item 3). Placeholder
  /// syntax `<ここに{key}>` (ja) / `<insert {key}>` (en) is intentional —
  /// concrete content like `"こんにちは"` was rejected because 2B-class
  /// models tend to parrot demonstrated content verbatim across all
  /// agents. Angle-bracketed meta-syntax avoids that trap.
  ///
  /// Consumes ``OutputSchema/fields`` order (primary-first) so the
  /// prompt example aligns with the GBNF grammar the LLM backend
  /// receives — single source of truth, see #194 PR#b. Alphabetical
  /// ordering would invert `inner_thought` before `statement` and
  /// break ``PartialOutputExtractor`` streaming UX.
  private func formatOutputSchema(_ schema: OutputSchema?, language: String) -> String? {
    guard let schema else { return nil }
    let spec =
      schema.fields
      .map { field in "\"\(field.name)\": \"string\"" }
      .joined(separator: ", ")
    let example =
      schema.fields
      .map { field in
        let placeholder = pickLanguage(
          language, ja: "<ここに\(field.name)>", en: "<insert \(field.name)>")
        return "\"\(field.name)\": \"\(placeholder)\""
      }
      .joined(separator: ", ")
    let header = pickLanguage(
      language, ja: "## 出力フォーマット（JSON）", en: "## Output Format (JSON)")
    let examplePrefix = pickLanguage(language, ja: "例", en: "Example")
    return """
      \(header)
      {\(spec)}
      \(examplePrefix): {\(example)}
      """
  }
}
