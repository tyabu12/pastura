import SwiftUI

// Per-run delete affordance for `ResultDetailView` (#545). Split into this
// sibling to keep the main view file under the 400-line `file_length` cap.
// The struct is a default-MainActor View, so this extension needs no
// `nonisolated` annotation (that rule is for Models/LLM/Engine/Data types).

extension ResultDetailView {
  /// Gate for the per-run delete menu item. Disabled until the record is
  /// loaded, and blocked while the run is still `.running`
  /// — deleting a row the engine may still be persisting to risks a
  /// write-vs-delete race. Paused / completed / failed / cancelled runs
  /// carry no live writer and are safe to remove.
  var canDelete: Bool {
    guard let status = simulation?.simulationStatus else { return false }
    return status != .running
  }

  /// Deletes this run (cascading to its turns / code-phase events via
  /// the `ON DELETE CASCADE` FKs) then pops back to the results list.
  ///
  /// The `router.pop()` is guarded on this detail view still being the
  /// top of the navigation stack: the user could swipe-back during the
  /// `offMain` delete (the gesture stays active via
  /// `preservesPasturaSwipeBackGesture`), and an unguarded pop would
  /// then remove a second, unrelated screen. On delete failure the view
  /// stays put and surfaces an alert. The guard matches on `simulationId`
  /// only; re-entry to the *same* run mid-delete (vanishingly unlikely
  /// given the single entry point) would still pop.
  func deleteThisRun() async {
    let simRepo = dependencies.simulationRepository
    let id = simulationId
    do {
      try await offMain { try simRepo.delete(id) }
    } catch {
      deleteError = String(
        format: String(localized: "Couldn't delete this run: %@"),
        error.localizedDescription)
      return
    }
    if router.path.last == .resultDetail(simulationId: id) {
      router.pop()
    }
  }
}

/// Attaches the per-run delete confirmation dialog + failure alert.
/// Extracted from `ResultDetailView.body` so the main file stays under
/// the `file_length` cap; the bindings and confirm action are owned by
/// the view.
struct ResultDeleteConfirmationModifier: ViewModifier {
  @Binding var isPresented: Bool
  @Binding var deleteError: String?
  let onConfirm: () async -> Void

  func body(content: Content) -> some View {
    content
      // `.alert` (not `.confirmationDialog`): under iOS 26 a
      // confirmationDialog triggered from a Menu item renders as a
      // popover whose arrow anchors to the body centre — pointing at
      // empty space, not the ⋯ button. An alert is a centred modal with
      // no anchor, so it presents correctly regardless of the trigger.
      .alert(
        String(localized: "Delete this run?"),
        isPresented: $isPresented
      ) {
        Button(String(localized: "Delete"), role: .destructive) {
          Task { await onConfirm() }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "This permanently removes this run and its conversation log. This can't be undone."
          ))
      }
      .alert(
        String(localized: "Delete failed"),
        isPresented: Binding(
          get: { deleteError != nil },
          set: { if !$0 { deleteError = nil } }
        )
      ) {
        Button(String(localized: "OK"), role: .cancel) { deleteError = nil }
      } message: {
        Text(deleteError ?? "")
      }
  }
}
