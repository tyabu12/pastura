import Foundation

/// Word wolf judge scoring logic.
///
/// Checks if the most-voted agent matches `state.variables["wolf_name"]`.
/// Emits a summary describing the result.
nonisolated struct WordwolfJudgeLogic: Sendable {

  func calculate(
    state: inout SimulationState,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    guard !state.voteResults.isEmpty else {
      emitter(.summary(text: "投票結果がありません"))
      return
    }

    let mostVoted = state.voteResults.max { $0.value < $1.value }?.key ?? ""
    let wolf = state.variables["wolf_name"] ?? "?"
    let voteCount = state.voteResults[mostVoted] ?? 0

    if mostVoted == wolf {
      emitter(
        .summary(text: "最多得票: \(mostVoted) (\(voteCount)票) — 多数派の勝ち！ウルフを見破った！")
      )
    } else {
      emitter(
        .summary(text: "最多得票: \(mostVoted) (\(voteCount)票) — ウルフの勝ち！逃げ切った！")
      )
    }
  }
}
