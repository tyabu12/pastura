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
  func injectNotes(into variables: inout [String: String], personaName: String) {
    variables["my_notes"] = variables["notes_\(personaName)"] ?? ""
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

    // Private reflect memo (#907): surface the agent's own prior-round note back
    // to itself only. Other agents never see it (it is not in the conversation
    // log), so the header stresses its privacy.
    if let note = state.variables["notes_\(persona.name)"], !note.isEmpty {
      let notesHeader = pickLanguage(
        language,
        ja: "## あなたの内心メモ（他の参加者には見えません）",
        en: "## Your Private Notes (invisible to other participants)")
      sections.append(
        """
        \(notesHeader)
        \(note)
        """)
    }

    sections.append(
      buildAnswerRules(scenario: scenario, persona: persona, phase: phase, state: state))

    if let formatSection = formatOutputSchema(OutputSchema.from(phase: phase), language: language) {
      sections.append(formatSection)
    }

    return sections.joined(separator: "\n\n")
  }

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
  private func buildAnswerRules(
    scenario: Scenario,
    persona: Persona,
    phase: Phase,
    state: SimulationState
  ) -> String {
    let language = scenario.engineLanguage
    var rules = pickLanguage(
      language,
      ja: """
        ## 回答ルール（厳守）
        - 必ず日本語で回答すること
        - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
        - 発言（statement などの本文フィールド）は3文以内で簡潔に書くこと（長い独白は禁止）
        - JSONは必ず1行で書くこと（改行を入れない）
        - JSON以外のテキストやコードブロック(```)は書かないこと
        - JSONに構文エラーがあると失敗扱いになる（カッコ・引用符・カンマを正しく閉じること）
        - {で始まり}で終わる単一オブジェクトのみ出力し、前後にテキストを付けないこと
        """,
      en: """
        ## Response Rules (strict)
        - Respond in English only.
        - Every field must contain a sentence (no empty "..." values).
        - Keep your statement (the main text field) concise: at most 3 sentences, no long monologues.
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
