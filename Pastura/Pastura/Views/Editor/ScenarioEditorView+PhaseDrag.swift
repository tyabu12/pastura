import SwiftUI

// Drag/drop + context-menu row for the top-level scenario phase list.
//
// Mirrors the sub-phase drag architecture in
// `PhaseEditorSheet+SubPhaseDrag.swift`:
// - Drag is scoped to the `line.3.horizontal` handle image (not the full
//   row) so `.contextMenu` (long-press) and `.onTapGesture` (tap-to-edit)
//   don't contend with `.draggable` for the same gesture.
// - `.dropDestination` draws a top-edge insertion line while hovered,
//   inserting at the hovered row's index.
// - `PhaseListTailDropZone` handles drops at the end of the list.
//
// A separate payload type (`TopLevelPhaseDragPayload`) prevents cross-layer
// contamination: a sub-phase payload cannot be dropped onto a top-level
// row — and vice versa — because `.dropDestination(for:)` filters by
// Transferable type.

/// One row in the scenario editor's top-level phase list.
///
/// Owns its own `isTargeted` state so only the hovered row shows the
/// top-edge insertion indicator.
struct PhaseRowView: View {
  @Binding var phases: [EditablePhase]
  let phase: EditablePhase
  let onEdit: () -> Void

  @State private var isTargeted = false

  private var index: Int {
    phases.firstIndex(where: { $0.id == phase.id }) ?? 0
  }

  private var totalCount: Int {
    phases.count
  }

  var body: some View {
    let blockRow = PhaseBlockRow(phase: phase)
    HStack(spacing: 10) {
      blockRow.handle
        .draggable(TopLevelPhaseDragPayload(id: phase.id)) {
          HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
              .foregroundStyle(.secondary)
            PhaseTypeLabel(phaseType: phase.type)
          }
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
      blockRow.content
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
      Spacer()
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(.background, in: RoundedRectangle(cornerRadius: 10))
    .overlay(alignment: .top) {
      if isTargeted {
        Rectangle()
          .fill(.tint)
          .frame(height: 2)
      }
    }
    .dropDestination(for: TopLevelPhaseDragPayload.self) { payloads, _ in
      guard let payload = payloads.first else { return false }
      phases.movePhase(id: payload.id, to: index)
      return true
    } isTargeted: {
      isTargeted = $0
    }
    .accessibilityLabel(accessibilityText)
    .accessibilityHint("Long-press for move options, tap to edit.")
    .contextMenu { contextMenuButtons }
  }

  private var accessibilityText: String {
    "Phase \(index + 1) of \(totalCount), \(phase.type.rawValue)"
  }

  @ViewBuilder
  private var contextMenuButtons: some View {
    Button {
      phases.movePhase(id: phase.id, to: index - 1)
    } label: {
      Label("Move Up", systemImage: "arrow.up")
    }
    .disabled(index == 0)

    Button {
      phases.movePhase(id: phase.id, to: index + 1)
    } label: {
      Label("Move Down", systemImage: "arrow.down")
    }
    .disabled(index >= totalCount - 1)
  }
}

/// Drop target that sits at the end of the top-level phase list so users
/// can drop a phase after the last existing row — or into an empty list.
///
/// When the list is empty, expands into a dashed-border "Drop here"
/// placeholder so the target is discoverable. When non-empty, collapses
/// to a slim strip that only draws the insertion line while hovered.
struct PhaseListTailDropZone: View {
  @Binding var phases: [EditablePhase]

  @State private var isTargeted = false

  var body: some View {
    Group {
      if phases.isEmpty {
        emptyListPlaceholder
      } else {
        tailHitStrip
      }
    }
    .contentShape(Rectangle())
    .dropDestination(for: TopLevelPhaseDragPayload.self) { payloads, _ in
      guard let payload = payloads.first else { return false }
      phases.movePhase(id: payload.id, to: phases.count)
      return true
    } isTargeted: {
      isTargeted = $0
    }
  }

  private var emptyListPlaceholder: some View {
    HStack {
      Spacer()
      Text(isTargeted ? "Drop here" : "No phases yet")
        .font(.caption)
        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
      Spacer()
    }
    .frame(minHeight: 32)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .stroke(
          isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
          style: StrokeStyle(lineWidth: 1, dash: [4])
        )
    )
    .accessibilityLabel("Phase list empty. Drop phases here.")
  }

  private var tailHitStrip: some View {
    Color.clear
      .frame(maxWidth: .infinity, minHeight: 12)
      .overlay(alignment: .top) {
        if isTargeted {
          Rectangle()
            .fill(.tint)
            .frame(height: 2)
        }
      }
      .accessibilityHidden(true)
  }
}
