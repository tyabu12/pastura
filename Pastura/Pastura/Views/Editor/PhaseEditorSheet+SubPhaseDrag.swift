import SwiftUI

// Drag/drop + context-menu UI for the conditional-phase editor's
// `then` / `else` sub-phase branches.
//
// Why this lives in a sibling file:
// - `PhaseEditorSheet.swift` already approaches SwiftLint's `file_length`
//   warning threshold; splitting keeps both files under 400 lines.
// - The drag pieces (row view, tail drop zone, context-menu actions) are
//   a cohesive feature cluster that does not need to interleave with the
//   non-conditional phase type sections above.
//
// Design notes:
// - Drag is scoped to the `line.3.horizontal` handle image — NOT the whole
//   row — so that `.contextMenu` (also long-press-activated) and
//   `.onTapGesture` (tap-to-edit) don't fight `.draggable` for the same
//   gesture. `.onDelete` (swipe) continues to work because it's applied to
//   the outer `ForEach`, independent of row content.
// - `.dropDestination(for:isTargeted:)` returns visual feedback through
//   per-row `isTargeted` state so the user sees a top-edge insertion line
//   at the hovered row. The branch's tail zone uses the same mechanism.
// - Within-branch reorder and cross-branch move go through the same
//   `EditablePhase.moveSubPhase(id:to:at:)` contract: row-level drops
//   insert at the hovered row's index, tail drops insert at `count`.

extension PhaseEditorSheet {
  @ViewBuilder
  func branchSection(
    title: String,
    branch: EditablePhase.Branch
  ) -> some View {
    Section(title) {
      ForEach(subPhases(in: branch)) { subPhase in
        SubPhaseRowView(
          phase: $phase,
          subPhase: subPhase,
          branch: branch,
          onEdit: {
            editingSubPhase = SubPhaseEditContext(branch: branch, phase: subPhase)
          }
        )
      }
      .onDelete { indexSet in
        removeSubPhases(at: indexSet, in: branch)
      }

      BranchTailDropZone(phase: $phase, branch: branch)

      Button {
        addSubPhase(to: branch)
      } label: {
        Label("Add sub-phase", systemImage: "plus.circle")
      }
    }
  }

  private func subPhases(in branch: EditablePhase.Branch) -> [EditablePhase] {
    branch == .then ? phase.thenPhases : phase.elsePhases
  }

  private func removeSubPhases(at indexSet: IndexSet, in branch: EditablePhase.Branch) {
    switch branch {
    case .then: phase.thenPhases.remove(atOffsets: indexSet)
    case .else: phase.elsePhases.remove(atOffsets: indexSet)
    }
  }

  private func addSubPhase(to branch: EditablePhase.Branch) {
    let newPhase = EditablePhase()
    switch branch {
    case .then: phase.thenPhases.append(newPhase)
    case .else: phase.elsePhases.append(newPhase)
    }
    editingSubPhase = SubPhaseEditContext(branch: branch, phase: newPhase)
  }
}

/// One row in a conditional phase's `then` / `else` branch.
///
/// Owns its own `isTargeted` state so only the hovered row shows the
/// top-edge insertion indicator. `@Binding var phase` propagates move
/// mutations back to the parent editor so branch arrays update in place.
private struct SubPhaseRowView: View {
  @Binding var phase: EditablePhase
  let subPhase: EditablePhase
  let branch: EditablePhase.Branch
  let onEdit: () -> Void

  @State private var isTargeted = false

  private var phases: [EditablePhase] {
    branch == .then ? phase.thenPhases : phase.elsePhases
  }

  private var index: Int {
    phases.firstIndex(where: { $0.id == subPhase.id }) ?? 0
  }

  private var totalCount: Int {
    phases.count
  }

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
        .draggable(SubPhaseDragPayload(id: subPhase.id, sourceBranch: branch)) {
          HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
              .foregroundStyle(.secondary)
            Text(subPhase.type.rawValue)
              .font(.body.monospaced())
          }
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }

      HStack {
        Text(subPhase.type.rawValue)
          .font(.body.monospaced())
          .foregroundStyle(.primary)
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
      .contentShape(Rectangle())
      .onTapGesture { onEdit() }
    }
    .contentShape(Rectangle())
    .overlay(alignment: .top) {
      if isTargeted {
        Rectangle()
          .fill(.tint)
          .frame(height: 2)
      }
    }
    .dropDestination(for: SubPhaseDragPayload.self) { payloads, _ in
      guard let payload = payloads.first else { return false }
      phase.moveSubPhase(id: payload.id, to: branch, at: index)
      return true
    } isTargeted: {
      isTargeted = $0
    }
    .accessibilityLabel(accessibilityText)
    .accessibilityHint("Long-press for move options, tap to edit.")
    .contextMenu { contextMenuButtons }
  }

  private var accessibilityText: String {
    let branchName = branch == .then ? "Then branch" : "Else branch"
    return "\(branchName), item \(index + 1) of \(totalCount), \(subPhase.type.rawValue)"
  }

  @ViewBuilder
  private var contextMenuButtons: some View {
    Button {
      phase.moveSubPhase(id: subPhase.id, to: branch, at: index - 1)
    } label: {
      Label("Move Up", systemImage: "arrow.up")
    }
    .disabled(index == 0)

    Button {
      phase.moveSubPhase(id: subPhase.id, to: branch, at: index + 1)
    } label: {
      Label("Move Down", systemImage: "arrow.down")
    }
    .disabled(index >= totalCount - 1)

    let other: EditablePhase.Branch = branch == .then ? .else : .then
    let otherLabel = other == .then ? "Move to Then Branch" : "Move to Else Branch"
    Button {
      let targetCount = other == .then ? phase.thenPhases.count : phase.elsePhases.count
      phase.moveSubPhase(id: subPhase.id, to: other, at: targetCount)
    } label: {
      Label(otherLabel, systemImage: "arrow.left.arrow.right")
    }
  }
}

/// Drop target that sits at the end of a branch so users can drop a
/// sub-phase after the last existing row — or into an empty branch.
///
/// Shows a dashed-border "Drop here" placeholder when the branch is
/// empty (both for discoverability and to communicate the drop target
/// even when no hover is active). When non-empty, the zone collapses to
/// a slim strip that only draws the insertion line while hovered.
private struct BranchTailDropZone: View {
  @Binding var phase: EditablePhase
  let branch: EditablePhase.Branch

  @State private var isTargeted = false

  private var phases: [EditablePhase] {
    branch == .then ? phase.thenPhases : phase.elsePhases
  }

  var body: some View {
    Group {
      if phases.isEmpty {
        emptyBranchPlaceholder
      } else {
        tailHitStrip
      }
    }
    .contentShape(Rectangle())
    .dropDestination(for: SubPhaseDragPayload.self) { payloads, _ in
      guard let payload = payloads.first else { return false }
      phase.moveSubPhase(id: payload.id, to: branch, at: phases.count)
      return true
    } isTargeted: {
      isTargeted = $0
    }
  }

  private var emptyBranchPlaceholder: some View {
    HStack {
      Spacer()
      Text(isTargeted ? "Drop here" : "No sub-phases yet")
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
    .accessibilityLabel(
      branch == .then
        ? "Then branch, empty. Drop sub-phases here."
        : "Else branch, empty. Drop sub-phases here."
    )
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
