import SwiftUI

/// Home nav-bar chip showing the currently-active LLM model with a status dot.
/// Tapping opens an inline `Menu` to switch among downloaded models (so the
/// display and the control share one place — no jump to the Settings tab to
/// change models), with a footer that opens Settings for download / delete.
///
/// Display + selectability semantics live in `ActiveModelChipPresenter`
/// (unit-tested); this view maps that semantic snapshot to color tokens and
/// localized copy, and routes selection through the shared
/// `AppDependencies.switchActiveModel(to:using:)` entry point.
struct ActiveModelChip: View {
  @Environment(ModelManager.self) private var modelManager
  @Environment(AppDependencies.self) private var dependencies
  @Environment(TabCoordinator.self) private var tabCoordinator

  private var presenter: ActiveModelChipPresenter {
    ActiveModelChipPresenter(
      activeDescriptor: modelManager.activeDescriptor,
      activeState: modelManager.activeState,
      catalog: modelManager.catalog,
      state: modelManager.state,
      activeModelID: modelManager.activeModelID,
      // Mirrors ModelSettingsRow.isSwitchLocked — switching is disabled while
      // a run (incl. a parked Phase B run) is in flight.
      isSimulationActive: dependencies.simulationActivityRegistry.isActive)
  }

  var body: some View {
    Menu {
      menuContent
    } label: {
      chipLabel
    }
    .accessibilityLabel(accessibilityLabel)
    .accessibilityIdentifier("home.activeModelChip")
  }

  // MARK: - Chip label

  private var chipLabel: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(dotColor)
        .frame(width: 7, height: 7)
      Text(presenter.chipLabel ?? String(localized: "No model"))
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.inkSecondary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 4)
      Image(systemName: "chevron.down")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Color.muted)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    // Fixed width so switching models never resizes the chip. A variable
    // width made the toolbar re-measure / animate the resize and clip the
    // wider name for a frame on every switch (geometryGroup, fixedSize, and
    // animation(nil) all failed to prevent it). A constant width removes the
    // resize entirely. 150 fits the longest shipped short name ("Gemma 4
    // E2B"); shorter names leave trailing space before the right-pinned
    // chevron (reads as a dropdown field), and a future long id truncates
    // with the tail ellipsis. Consistent 150 on SE-width still needs a glance
    // in real-device QA (no simulator signal for nav-bar layout).
    .frame(width: 150)
    .background(Capsule().fill(Color.mossDark.opacity(0.10)))
  }

  private var dotColor: Color {
    switch presenter.statusDot {
    case .ready: Color.mossDark
    case .working: Color.warning
    case .inactive: Color.muted
    case .problem: Color.danger
    }
  }

  // MARK: - Menu

  @ViewBuilder private var menuContent: some View {
    Section {
      ForEach(presenter.rows) { row in
        Button {
          select(row)
        } label: {
          rowLabel(row)
        }
        .disabled(!row.isSelectable)
      }
    } header: {
      Text(String(localized: "Active model"))
    }

    Button {
      // Download / delete is heavier management — that stays in Settings.
      tabCoordinator.handleSelection(.settings)
    } label: {
      Label(String(localized: "Manage in Settings"), systemImage: "gearshape")
    }
  }

  private func rowLabel(_ row: ActiveModelChipPresenter.MenuRow) -> some View {
    // Ready rows show just the name; non-ready rows append the localized
    // availability hint. Compose into one verbatim string so the runtime value
    // is never used as a catalog lookup key (the LocalizedStringKey
    // interpolation fallback trap, i18n.md); `Label`/`Text` take the String
    // (verbatim) overloads.
    let composed = row.detail.map { "\(row.name) · \(detailText($0))" } ?? row.name
    return Group {
      if row.isActive {
        Label(composed, systemImage: "checkmark")
      } else {
        Text(verbatim: composed)
      }
    }
  }

  private func detailText(_ detail: ActiveModelChipPresenter.RowDetail) -> String {
    switch detail {
    case .downloading: String(localized: "Downloading…")
    case .notDownloaded: String(localized: "Not downloaded")
    case .unavailable: String(localized: "Unavailable")
    }
  }

  private var accessibilityLabel: String {
    guard let label = presenter.chipLabel else {
      return String(localized: "No active model")
    }
    return String(format: String(localized: "Active model: %@"), label)
  }

  // MARK: - Actions

  private func select(_ row: ActiveModelChipPresenter.MenuRow) {
    guard row.isSelectable,
      let descriptor = modelManager.catalog.first(where: { $0.id == row.id })
    else { return }
    dependencies.switchActiveModel(to: descriptor, using: modelManager)
  }
}
