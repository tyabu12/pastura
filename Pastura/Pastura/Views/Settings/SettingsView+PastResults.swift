import SwiftUI

// "Clear all results" affordance for `SettingsView` (#545). Split into this
// sibling to keep `SettingsView` under the file_length / type_body_length
// caps. `SettingsView` is a default-MainActor View, so this extension needs
// no `nonisolated` annotation.

extension SettingsView {
  /// Whether clear-all is blocked because a simulation is in flight.
  /// Mirrors the Models section's model-switch gate
  /// (`simulationActivityRegistry.isActive`) — clearing every run while
  /// the engine is still persisting one risks a write-vs-delete race.
  var isClearAllBlocked: Bool {
    dependencies.simulationActivityRegistry.isActive
  }

  /// Destructive "Clear all results" affordance. Available on both
  /// device and simulator (past results exist on both). Gated by
  /// `isClearAllBlocked`; the confirmation dialog is the consent step.
  @ViewBuilder
  var pastResultsSection: some View {
    VStack(alignment: .leading, spacing: 7) {
      PasturaSection(String(localized: "Past Results")) {
        Button {
          isShowingClearAllConfirm = true
        } label: {
          HStack {
            Text(String(localized: "Clear all results"))
              // Explicit `Color.danger` (not `.danger`) — Color extension
              // tokens don't resolve through the ShapeStyle overload.
              .foregroundStyle(isClearAllBlocked ? Color.muted : Color.danger)
            Spacer()
          }
          .padding(.horizontal, 17)
          .padding(.vertical, 15)
          .contentShape(Rectangle())
        }
        .disabled(isClearAllBlocked)
        .accessibilityIdentifier("settings.clearAllResultsButton")
      }
      if isClearAllBlocked {
        Text(String(localized: "Finish the current simulation before clearing results."))
          .font(.caption)
          .foregroundStyle(Color.muted)
          .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
      }
    }
  }

  /// Deletes every past run (cascading to turns / code-phase events) and
  /// reclaims space via VACUUM, off the main actor. Surfaces an alert on
  /// failure.
  func clearAllResults() async {
    let simRepo = dependencies.simulationRepository
    do {
      try await offMain { try simRepo.deleteAll() }
    } catch {
      clearAllError = String(
        format: String(localized: "Couldn't clear results: %@"),
        error.localizedDescription)
    }
  }
}

/// Attaches the clear-all confirmation dialog + failure alert. Extracted
/// from `SettingsView.body` so the main file stays under its line caps;
/// the bindings and confirm action are owned by the view.
struct ClearAllConfirmationModifier: ViewModifier {
  @Binding var isPresented: Bool
  @Binding var error: String?
  let onConfirm: () async -> Void

  func body(content: Content) -> some View {
    content
      // `.alert` (not `.confirmationDialog`) for the same reason as the
      // per-run delete — see `ResultDeleteConfirmationModifier`: iOS 26
      // renders confirmationDialogs as mis-anchored popovers. A centred
      // alert presents correctly.
      .alert(
        String(localized: "Clear all results?"),
        isPresented: $isPresented
      ) {
        Button(String(localized: "Clear all results"), role: .destructive) {
          Task { await onConfirm() }
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "This permanently removes every past run and its conversation log. This can't be undone."
          ))
      }
      .alert(
        String(localized: "Clear failed"),
        isPresented: Binding(
          get: { error != nil },
          set: { if !$0 { error = nil } }
        )
      ) {
        Button(String(localized: "OK"), role: .cancel) { error = nil }
      } message: {
        Text(error ?? "")
      }
  }
}
