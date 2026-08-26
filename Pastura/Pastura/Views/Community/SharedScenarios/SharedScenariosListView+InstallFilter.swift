import SwiftUI

// Install-state filter UI for the Browse tab (#1565, ADR-025 § Amendment
// 2026-08-26), split out of `SharedScenariosListView` like the category chips
// (#731) to stay under the type_body_length budget. Two surfaces: the toolbar
// filter menu (the control) and the footer hint (the explanation — a row
// hidden by default must never look like a missing scenario).
extension SharedScenariosListView {

  /// Toolbar filter menu. A `Menu` rather than a third chip row: the language
  /// and category chips already occupy the top of the `ScrollView`, and every
  /// extra row there pushes the first card further down — undoing part of
  /// what the scroll-restoration fix in the same change bought.
  ///
  /// System `Menu` + `Image` label, so the iOS 26 Liquid Glass capsule is the
  /// stock toolbar look — no `hidingPasturaSharedBackground()` (that opt-out
  /// is for custom-drawn controls such as `PasturaBackButton`).
  func installFilterMenu(viewModel: SharedScenariosViewModel) -> some View {
    let showsInstalled = viewModel.installFilter == .all
    return Menu {
      Toggle(
        isOn: Binding(
          get: { viewModel.installFilter == .all },
          set: { viewModel.installFilter = $0 ? .all : .hideInstalled })
      ) {
        Label(
          String(localized: "Show installed scenarios"),
          systemImage: "checkmark.circle")
      }
    } label: {
      // Filled variant marks the non-default state so a user who toggled it
      // on can see why installed rows are back without opening the menu.
      Image(
        systemName: showsInstalled
          ? "line.3.horizontal.decrease.circle.fill"
          : "line.3.horizontal.decrease.circle")
    }
    .accessibilityLabel(String(localized: "Filter"))
    .accessibilityIdentifier("sharedScenarios.installFilterMenu")
  }

  /// "N installed scenarios hidden · Show" line under the catalog. Rendered
  /// only while the hide filter actually removed something, so the default
  /// state on a fresh install (nothing installed yet) shows no footer.
  @ViewBuilder
  func hiddenInstalledFooter(viewModel: SharedScenariosViewModel) -> some View {
    let count = viewModel.hiddenInstalledCount
    if count > 0 {
      HStack(spacing: 8) {
        // Plural: the `Int` interpolation inside `Text` is the sanctioned
        // exception to Form B — it drives `variations.plural` selection
        // (.claude/rules/i18n-ui.md § Plurals). Key: "%lld installed scenarios
        // hidden", `extractionState: manual`.
        Text("\(count) installed scenarios hidden")
          .font(.caption)
          .foregroundStyle(Color.muted)
        Button(String(localized: "Show")) {
          viewModel.installFilter = .all
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.mossDark)
        .buttonStyle(.plain)
        .accessibilityIdentifier("sharedScenarios.showInstalledButton")
        Spacer(minLength: 0)
      }
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin + 6)
      .accessibilityIdentifier("sharedScenarios.hiddenInstalledFooter")
    }
  }
}
