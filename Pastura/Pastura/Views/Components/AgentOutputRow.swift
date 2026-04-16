import SwiftUI

/// Displays a single agent's output with expandable inner thought and an
/// optional LLM-chat-style typing animation for the latest row.
///
/// Typing is gated by `isLatest` and `charsPerSecond`: only the newest row
/// animates; older rows (and every row when the user picks `.instant` speed)
/// render their full text immediately. When `isLatest` flips from `true` →
/// `false` — because a newer agentOutput arrived, or because this row was
/// recycled by `LazyVStack` after scrolling off-screen — the animation snaps
/// to completion instead of replaying on re-appearance.
struct AgentOutputRow: View {
  let agent: String
  let output: TurnOutput
  let phaseType: PhaseType
  let showAllThoughts: Bool
  /// `true` when this row is the most recent agent output. Only the latest
  /// row animates typing; older rows render full text immediately.
  var isLatest: Bool = false
  /// Characters revealed per second during typing. `nil` = no animation.
  var charsPerSecond: Double?

  @State private var showInnerThought = false
  @State private var visibleChars: Int = 0
  @State private var animationTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Agent name + phase
      HStack(alignment: .firstTextBaseline) {
        Text(agent)
          .font(.subheadline.bold())
        PhaseTypeLabel(phaseType: phaseType)
        Spacer()
      }

      // Main output text — animated character-by-character when applicable.
      if let text = primaryText {
        Text(displayedPrimary(fullText: text))
          .font(.body)
      }

      // Inner thought (tap to reveal, or always shown via global toggle)
      if let thought = output.innerThought, !thought.isEmpty {
        if !showAllThoughts {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              showInnerThought.toggle()
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: showInnerThought ? "eye.slash" : "eye")
              Text(showInnerThought ? "Hide thought" : "Show thought")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }

        if showAllThoughts || showInnerThought {
          Text(thought)
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .padding(.leading, 8)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
    }
    .padding(.vertical, 4)
    .onAppear { startAnimationIfNeeded() }
    .onChange(of: isLatest) { _, newValue in
      if !newValue { snapToFull() }
    }
    .onDisappear { animationTask?.cancel() }
  }

  /// Returns either the fully-revealed text (when animation is off or done)
  /// or a prefix matching the current `visibleChars` count.
  private func displayedPrimary(fullText: String) -> String {
    guard isLatest, charsPerSecond != nil, visibleChars < fullText.count else {
      return fullText
    }
    let endIndex = fullText.index(fullText.startIndex, offsetBy: visibleChars)
    return String(fullText[..<endIndex])
  }

  private func startAnimationIfNeeded() {
    guard let text = primaryText, !text.isEmpty else { return }
    guard isLatest, let cps = charsPerSecond, cps > 0 else {
      // Not the latest row or user chose instant — skip animation entirely.
      return
    }
    let total = text.count
    if visibleChars >= total { return }  // already finished before a re-appear

    animationTask?.cancel()
    let delayNanos = UInt64(1_000_000_000.0 / cps)
    animationTask = Task { @MainActor in
      while !Task.isCancelled && visibleChars < total {
        try? await Task.sleep(nanoseconds: delayNanos)
        if Task.isCancelled { return }
        visibleChars = min(visibleChars + 1, total)
      }
    }
  }

  private func snapToFull() {
    animationTask?.cancel()
    if let text = primaryText {
      visibleChars = text.count
    }
  }

  /// Extracts the primary display text from the output based on phase type.
  private var primaryText: String? {
    switch phaseType {
    case .speakAll, .speakEach:
      output.statement ?? output.declaration ?? output.boke
    case .vote:
      output.vote.map { vote in
        let reason = output.reason.map { " (\($0))" } ?? ""
        return "→ \(vote)\(reason)"
      }
    case .choose:
      output.action ?? output.declaration
    default:
      output.fields.values.first
    }
  }
}
