import Foundation

/// Builds LLM prompts for simulation phases.
///
/// Handles template variable expansion, system prompt construction with persona
/// and scenario context, and conversation log formatting for prompt injection.
nonisolated struct PromptBuilder: Sendable {

  /// Priority-ordered list of field names considered "main" output fields.
  /// Used to determine which field goes into the conversation log.
  private static let mainFieldPriority = [
    "statement", "declaration", "boke", "speech", "response", "answer"
  ]

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
  /// Returns `"（まだなし）"` for an empty log, matching the prototype's behavior.
  func formatConversationLog(_ entries: [ConversationEntry]) -> String {
    if entries.isEmpty {
      return "（まだなし）"
    }
    return entries.map { "  \($0.agentName): \($0.content)" }.joined(separator: "\n")
  }

  // MARK: - Main Field Detection

  /// Returns the primary output field name for a phase.
  ///
  /// Checks the phase's `outputSchema` keys against a priority list of known speech-like
  /// field names. Falls back to `"statement"` to avoid non-deterministic dictionary iteration.
  func getMainField(phase: Phase) -> String {
    guard let schema = phase.outputSchema else { return "statement" }
    for candidate in Self.mainFieldPriority where schema[candidate] != nil {
      return candidate
    }
    return "statement"
  }

  // MARK: - System Prompt

  /// Builds the system prompt for an agent's LLM call.
  ///
  /// Includes: scenario context, persona description, answer rules (Japanese output,
  /// no empty fields, single-line JSON), output format specification, and phase-specific
  /// constraints (options for choose, candidate list for vote).
  func buildSystemPrompt(
    scenario: Scenario,
    persona: Persona,
    phase: Phase,
    state: SimulationState
  ) -> String {
    var sections: [String] = []

    // Header
    sections.append(
      "あなたはシミュレーションの参加者です。キャラクターになりきってください。")

    // Scenario context
    sections.append(
      """
      ## シナリオ
      \(scenario.context)
      """)

    // Persona
    sections.append(
      """
      ## あなたのキャラクター
      名前: \(persona.name)
      \(persona.description)
      """)

    // Answer rules
    var rules = """
      ## 回答ルール（厳守）
      - 必ず日本語で回答すること
      - 全フィールドに必ず文章を書くこと（空欄「...」は禁止）
      - JSONは必ず1行で書くこと（改行を入れない）
      - JSON以外のテキストやコードブロック(```)は書かないこと
      """

    // Phase-specific constraints
    if phase.type == .choose, let options = phase.options {
      let optionsList = options.joined(separator: ", ")
      rules += "\n- actionフィールドは必ず次のいずれかを書くこと: \(optionsList)"
    }

    if phase.type == .vote {
      let excludeSelf = phase.excludeSelf ?? true
      let candidates = scenario.personas
        .map(\.name)
        .filter { name in
          if excludeSelf && name == persona.name { return false }
          if state.eliminated[name] == true { return false }
          return true
        }
      let candidatesList = candidates.joined(separator: ", ")
      rules +=
        "\n- voteフィールドは必ず次の名前のいずれかを正確に書くこと: \(candidatesList)"
    }

    sections.append(rules)

    // Output format
    if let schema = phase.outputSchema {
      let spec = schema.map { "\"\($0.key)\": \"\($0.value)\"" }
        .sorted()  // Deterministic output order
        .joined(separator: ", ")
      sections.append(
        """
        ## 出力フォーマット（JSON）
        {\(spec)}
        """)
    }

    return sections.joined(separator: "\n\n")
  }
}
