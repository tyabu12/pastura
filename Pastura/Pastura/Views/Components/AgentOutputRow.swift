import SwiftUI

/// Displays a single agent's output with expandable inner thought.
struct AgentOutputRow: View {
  let agent: String
  let output: TurnOutput
  let phaseType: PhaseType
  let showAllThoughts: Bool

  @State private var showInnerThought = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Agent name + phase
      HStack(alignment: .firstTextBaseline) {
        Text(agent)
          .font(.subheadline.bold())
        PhaseTypeLabel(phaseType: phaseType)
        Spacer()
      }

      // Main output text
      if let text = primaryText {
        Text(text)
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
