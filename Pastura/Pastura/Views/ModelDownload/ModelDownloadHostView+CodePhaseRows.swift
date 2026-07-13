import SwiftUI

// Inline code-phase narration rows for the DL-time demo replay chat stream
// (#932) — the demo counterpart of the live simulation's inline log entries
// (`SimulationView+LogEntries.swift`). Split out of `+ChatStream` so both stay
// under swiftlint's 400-line `file_length` cap, mirroring the live split.
//
// These deliberately REPLICATE the live helpers rather than share them: the
// live versions are methods on the `SimulationView` extension and are wired to
// its per-entry `opacity(forEntryId:)` reveal animation, which the demo does
// not have. The demo already replicates rather than shares its agent row
// (`demoAgentRow`), so this follows the same seam. The design tokens
// (`Typography.*`, `Color.*`) and the `String(localized:)` keys are copied
// byte-for-byte from the live helpers so the two chat streams stay visually
// unified (#273) and no new catalog key is spawned — a whitespace drift in a
// format string (e.g. the two leading spaces in `"  %@: %lld votes"`) would
// fork a key.
extension ModelDownloadHostView {

  /// One inline code-phase line, dispatched by ``ReplayViewModel/CodePhaseLine``
  /// variant. `.transition` + `.id` mirror the demo's other chat rows
  /// (`demoAgentRow` / `demoIntroCard`) so it animates in and scroll-follows
  /// identically.
  @ViewBuilder
  func demoCodePhaseRow(id: UUID, line: ReplayViewModel.CodePhaseLine) -> some View {
    codePhaseContent(line)
      .frame(maxWidth: .infinity, alignment: .leading)
      .id(id)
      .transition(reduceMotion ? .identity : .opacity)
  }

  @ViewBuilder
  private func codePhaseContent(_ line: ReplayViewModel.CodePhaseLine) -> some View {
    switch line {
    case .assignment(let agent, let value):
      // Mirrors `SimulationView.assignmentEntry`.
      Text(String(format: String(localized: "%@ assigned: %@"), agent, value))
        .textStyle(Typography.metaValue)
        .foregroundStyle(Color.muted)
    case .sharedAssignment(let value):
      // Mirrors `SimulationView.sharedAssignmentEntry` (#939): the round's
      // premise gets a moss accent rule + clipboard icon + body-weight ink text,
      // no "Topic:" label. `Text(verbatim:)` — dynamic content, not a key.
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        Image(systemName: "list.clipboard")
          .foregroundStyle(Color.mossDark)
        Text(verbatim: value)
          .textStyle(Typography.bodyBubble)
          .foregroundStyle(Color.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, 11)
      .overlay(alignment: .leading) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(Color.moss)
          .frame(width: 3)
      }
    case .summary(let text):
      // Mirrors `SimulationView.summaryEntry`.
      Text(text)
        .textStyle(Typography.bodyBubble)
        .foregroundStyle(Color.inkSecondary)
    case .narration(let text):
      // Mirrors `ResultDetailView.narrationRow` — same `.summary` shape with
      // a 📺 marker so it reads as commentator copy.
      Text("📺 \(text)")
        .textStyle(Typography.bodyBubble)
        .foregroundStyle(Color.inkSecondary)
    case .voteResults(let tallies):
      voteResultsContent(tallies)
    case .scoreUpdate(let scores):
      scoresContent(scores)
    case .elimination(let agent, let voteCount):
      // Mirrors `SimulationView.eliminationEntry`.
      HStack(spacing: 4) {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(Color.inkSecondary)
        Text(String(format: String(localized: "%@ eliminated (%lld votes)"), agent, voteCount))
          .textStyle(Typography.titlePhase)
      }
    case .pairingResult(let agent1, let action1, let agent2, let action2):
      pairingResultContent(agent1: agent1, action1: action1, agent2: agent2, action2: action2)
    case .eventInjected(let event):
      eventInjectedContent(event)
    }
  }

  /// Mirrors `SimulationView.voteResultsEntry`.
  private func voteResultsContent(_ tallies: [String: Int]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(String(localized: "Vote Results"))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      ForEach(tallies.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
        Text(String(format: String(localized: "  %@: %lld votes"), name, count))
          .textStyle(Typography.metaValue)
      }
    }
    .foregroundStyle(Color.muted)
  }

  /// Mirrors `SimulationView.scoresSummary`.
  private func scoresContent(_ scores: [String: Int]) -> some View {
    HStack(spacing: 8) {
      ForEach(scores.sorted(by: { $0.value > $1.value }).prefix(5), id: \.key) { name, score in
        Text(verbatim: "\(name):\(score)")
          .textStyle(Typography.metaValue)
          .monospacedDigit()
      }
    }
    .foregroundStyle(Color.muted)
  }

  /// Mirrors `SimulationView.pairingResultEntry`.
  private func pairingResultContent(
    agent1: String, action1: String, agent2: String, action2: String
  ) -> some View {
    HStack {
      Text(verbatim: "\(agent1)(\(action1))")
      Text(String(localized: "vs"))
        .foregroundStyle(Color.muted)
      Text(verbatim: "\(agent2)(\(action2))")
    }
    .textStyle(Typography.titlePhase)
  }

  /// Mirrors `SimulationView.eventInjectedEntry`. The miss case (`event == nil`)
  /// renders an explicit "no event" marker rather than disappearing — users
  /// observing a probabilistic phase need to see the dice roll, not just hits.
  @ViewBuilder
  private func eventInjectedContent(_ event: String?) -> some View {
    if let event {
      HStack(spacing: 4) {
        Image(systemName: "die.face.5").foregroundStyle(Color.inkSecondary)
        Text(event)
          .textStyle(Typography.bodyBubble)
          .foregroundStyle(Color.inkSecondary)
      }
    } else {
      Text(String(localized: "No event this round"))
        .textStyle(Typography.metaValue)
        .foregroundStyle(Color.muted)
    }
  }

  // MARK: - Lifecycle chapter separators (#932 follow-up)

  /// Full-width round separator, mirroring `SimulationView.roundSeparator`.
  /// Reuses the `"Round %lld / %lld"` key already wired into `GameHeader` so the
  /// separator label and header label stay translation-aligned.
  func demoRoundSeparator(id: UUID, round: Int, totalRounds: Int) -> some View {
    HStack {
      Rectangle().fill(Color.rule).frame(height: 1)
      Text(String(format: String(localized: "Round %lld / %lld"), round, totalRounds))
        .textStyle(Typography.metaLabel)
        .foregroundStyle(Color.inkSecondary)
      Rectangle().fill(Color.rule).frame(height: 1)
    }
    .padding(.vertical, 4)
    .id(id)
    .transition(reduceMotion ? .identity : .opacity)
  }

  /// Phase separator, mirroring the live sim's `.phaseStarted` dispatch: LLM
  /// phases (speak / vote / choose) get a full-width chapter rule around a
  /// `PhaseTypeLabel`; code phases (assign / score_calc / summarize) keep the
  /// inline badge to avoid over-chunking code-phase-heavy scenarios (#882).
  @ViewBuilder
  func demoPhaseSeparator(id: UUID, phaseType: PhaseType) -> some View {
    Group {
      if phaseType.requiresLLM {
        HStack {
          Rectangle().fill(Color.rule).frame(height: 1)
          PhaseTypeLabel(phaseType: phaseType)
          Rectangle().fill(Color.rule).frame(height: 1)
        }
        .padding(.vertical, 4)
      } else {
        PhaseTypeLabel(phaseType: phaseType)
          .padding(.top, 4)
      }
    }
    .id(id)
    .transition(reduceMotion ? .identity : .opacity)
  }
}
