import SwiftUI

/// A compact card row representing a single phase in the scenario editor's phase list.
///
/// Displays a drag handle, the phase type badge, and a brief content summary.
/// The `handle` and `content` subviews are exposed separately so the drag-
/// enabled row in the scenario editor can attach `.draggable` to the handle
/// alone, leaving tap + context-menu long-press gestures on the content.
struct PhaseBlockRow: View {
  let phase: EditablePhase

  var body: some View {
    HStack(spacing: 10) {
      handle
      content
      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(.background, in: RoundedRectangle(cornerRadius: 10))
  }

  /// Drag-handle icon. Exposed separately so callers that want to scope
  /// `.draggable` to the handle (instead of the whole row) can attach the
  /// modifier here.
  var handle: some View {
    Image(systemName: "line.3.horizontal")
      .foregroundStyle(.secondary)
      .frame(width: 20)
      .accessibilityHidden(true)
  }

  /// Non-handle portion of the row — phase type badge + content summary.
  var content: some View {
    HStack(spacing: 10) {
      PhaseTypeLabel(phaseType: phase.type)
      Text(summary)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  /// A brief human-readable summary of the phase content.
  private var summary: String {
    switch phase.type {
    case .speakAll, .speakEach, .vote, .choose:
      return phase.prompt.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines)
    case .scoreCalc:
      return phase.logic?.rawValue ?? "—"
    case .assign:
      let src = phase.source.isEmpty ? "?" : phase.source
      let dst = phase.target.isEmpty ? "?" : phase.target
      return "\(src) → \(dst)"
    case .eliminate:
      return ""
    case .summarize:
      return phase.template.prefix(50).trimmingCharacters(in: .whitespacesAndNewlines)
    case .conditional:
      // Compact summary: condition expression + branch counts. Nested
      // sub-phases are edited via a nested sheet from `PhaseEditorSheet`
      // so we don't render them here (single row per top-level phase).
      let condition =
        phase.condition
        .prefix(40)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let then = phase.thenPhases.count
      let elseCount = phase.elsePhases.count
      if condition.isEmpty {
        return "(no condition)"
      }
      return "\(condition) → then:\(then) else:\(elseCount)"
    }
  }
}
