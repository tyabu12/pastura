import SwiftUI

/// Displays a phase type as a colored badge.
struct PhaseTypeLabel: View {
  let phaseType: PhaseType

  var body: some View {
    Text(phaseType.rawValue)
      .font(.caption.monospaced())
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(backgroundColor.opacity(0.15), in: Capsule())
      .foregroundStyle(backgroundColor)
  }

  private var backgroundColor: Color {
    if phaseType.requiresLLM {
      .purple
    } else {
      .orange
    }
  }
}
