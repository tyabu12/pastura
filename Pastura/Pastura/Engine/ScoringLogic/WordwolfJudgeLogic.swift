import Foundation

/// Word wolf judge scoring logic.
///
/// Checks if the most-voted agent matches `state.variables["wolf_name"]`.
/// Emits a summary describing the result in `scenario.language` (ADR-010
/// D7 / D8 — scenario-language-bound, so `String(format:)` is used with
/// literal English / Japanese rather than `String(localized:)`).
nonisolated struct WordwolfJudgeLogic: Sendable {

  func calculate(
    state: inout SimulationState,
    language: String,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    guard !state.voteResults.isEmpty else {
      emitter(
        .summary(
          text: pickLanguage(language, ja: "投票結果がありません", en: "No votes recorded")))
      return
    }

    let mostVoted = state.voteResults.max { $0.value < $1.value }?.key ?? ""
    let wolf = state.variables["wolf_name"] ?? "?"
    let voteCount = state.voteResults[mostVoted] ?? 0

    if mostVoted == wolf {
      let format = pickLanguage(
        language,
        ja: "最多得票: %@ (%lld票) — 多数派の勝ち！ウルフを見破った！",
        en: "Most votes: %@ (%lld) — Majority wins! The wolf was found.")
      emitter(
        .summary(text: String(format: format, mostVoted, Int64(voteCount)))
      )
    } else {
      let format = pickLanguage(
        language,
        ja: "最多得票: %@ (%lld票) — ウルフの勝ち！逃げ切った！",
        en: "Most votes: %@ (%lld) — The wolf wins! Escaped detection.")
      emitter(
        .summary(text: String(format: format, mostVoted, Int64(voteCount)))
      )
    }
  }
}
