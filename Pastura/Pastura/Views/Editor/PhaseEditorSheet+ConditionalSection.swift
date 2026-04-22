import SwiftUI

// Conditional-phase UI for `PhaseEditorSheet`: the condition field plus
// the Then / Else branch sections with their `.contextMenu`-based
// cross-branch move action.
//
// Split out from `PhaseEditorSheet.swift` to keep that file under
// SwiftLint's `file_length` limit. Accesses `phase` and
// `editingSubPhase` from the parent struct — both intentionally
// internal so this extension can drive nested-sheet presentation.

extension PhaseEditorSheet {
  var conditionalSection: some View {
    Group {
      Section {
        TextField(
          "e.g. max_score >= 10",
          text: $phase.condition,
          axis: .vertical
        )
        .font(.body.monospaced())
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      } header: {
        Text("Condition")
      } footer: {
        Text(
          "Single comparison: lhs OP rhs where OP is one of ==, !=, <, <=, >, >=. "
            + "Identifiers: current_round, total_rounds, max_score, min_score, "
            + "eliminated_count, active_count, vote_winner, scores.<Name>, "
            + "or any template variable. Wrap string literals in double quotes."
        )
        .font(.caption)
      }

      branchSection(
        title: "Then branch (condition true)",
        phases: $phase.thenPhases,
        branch: .then
      )
      branchSection(
        title: "Else branch (condition false)",
        phases: $phase.elsePhases,
        branch: .else
      )
    }
  }

  @ViewBuilder
  fileprivate func branchSection(
    title: String,
    phases: Binding<[EditablePhase]>,
    branch: EditablePhase.Branch
  ) -> some View {
    Section {
      ForEach(phases.wrappedValue) { subPhase in
        Button {
          editingSubPhase = SubPhaseEditContext(branch: branch, phase: subPhase)
        } label: {
          HStack {
            Text(subPhase.type.rawValue)
              .font(.body.monospaced())
              .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
        }
        .contextMenu {
          Button {
            phase.moveSubPhase(id: subPhase.id, to: branch == .then ? .else : .then)
          } label: {
            Label(
              branch == .then ? "Move to Else Branch" : "Move to Then Branch",
              systemImage: "arrow.left.arrow.right"
            )
          }
        }
      }
      .onDelete { indexSet in
        phases.wrappedValue.remove(atOffsets: indexSet)
      }
      .onMove { source, destination in
        // Within-branch reorder via .onMove. Cross-branch move is exposed
        // via the .contextMenu on each row.
        phases.wrappedValue.move(fromOffsets: source, toOffset: destination)
      }

      Button {
        let newPhase = EditablePhase()
        phases.wrappedValue.append(newPhase)
        editingSubPhase = SubPhaseEditContext(branch: branch, phase: newPhase)
      } label: {
        Label("Add sub-phase", systemImage: "plus.circle")
      }
    } header: {
      Text(title)
    } footer: {
      Text("Long-press a sub-phase to move it to the other branch.")
        .font(.caption)
    }
  }
}
