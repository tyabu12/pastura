import SwiftUI

/// Bottom contextual action bar for ``ScenarioDetailView`` — replaces the tab
/// bar on the scenario-detail screen (ADR-016 § Amendment / contextual bottom
/// action bar). Tab-bar-style: equal-width columns, **icon over label**, so it
/// reads as the tab bar "changing" into Run / Edit·Template / Delete.
///
/// Why custom (not a native `.bottomBar`): iOS 26's `.bottomBar` renders
/// **icon-only** (the design language moved from text to symbols) and offers no
/// icon-over-label form — that vertical layout is a `TabView` construct. To
/// keep visible text labels *and* the Liquid Glass continuity with the native
/// tab bar it replaces, this applies `glassEffect` (iOS 26+) to a custom bar,
/// with a `.regularMaterial` fallback on iOS 18–25.
///
/// Colours carry the design-system §5.8 intent: Run = `mossDark` (primary),
/// Edit·Template = `ink` (secondary), Delete = `dangerInk` (destructive).
///
/// The glass rendering is **real-device QA** — the simulator mis-renders iOS 26
/// bottom chrome (swiftui-traps.md § 5.8) — as is the `InFlightSimulationIndicator`
/// pill's clearance above this bar.
struct ScenarioDetailActionBar: View {
  let scenarioId: String
  let scenarioName: String
  let canRun: Bool
  /// Backs Edit / Use-as-Template / Delete. `nil` during the brief load window
  /// renders Run only.
  let record: ScenarioRecord?
  let isGallerySourced: Bool
  /// Triggers the host's delete-confirmation `.alert`.
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      runItem
      if let record {
        editOrTemplateItem(record: record)
        if !record.isPreset {
          deleteItem
        }
      }
    }
    .padding(.top, Spacing.xxs)
    .frame(maxWidth: .infinity)
    .pasturaBottomActionBarSurface()
  }

  /// Primary. Tap-driven push → `NavigationLink(value:)` (navigation.md);
  /// `initialName` feeds SimulationView's title from the first frame
  /// (identity-neutral via `RouteHint`, ADR-008).
  private var runItem: some View {
    NavigationLink(
      value: Route.simulation(
        scenarioId: scenarioId, initialName: .init(scenarioName))
    ) {
      actionColumn(
        title: String(localized: "Run"), systemImage: "play.fill",
        tint: Color.mossDark)
    }
    .buttonStyle(.plain)
    .disabled(!canRun)
    .opacity(canRun ? 1 : 0.4)
    .accessibilityLabel(String(localized: "Run Simulation"))
    .accessibilityIdentifier("scenarioDetail.runSimulationButton")
  }

  /// Read-only sources (preset / installed gallery copy) clone as a template;
  /// user scenarios edit directly.
  @ViewBuilder
  private func editOrTemplateItem(record: ScenarioRecord) -> some View {
    if record.isPreset || isGallerySourced {
      NavigationLink(value: Route.editor(templateYAML: record.yamlDefinition)) {
        actionColumn(
          title: String(localized: "Use as Template"), systemImage: "doc.on.doc",
          tint: Color.ink)
      }
      .buttonStyle(.plain)
    } else {
      NavigationLink(value: Route.editor(editingId: scenarioId)) {
        actionColumn(
          title: String(localized: "Edit"), systemImage: "pencil", tint: Color.ink)
      }
      .buttonStyle(.plain)
    }
  }

  /// Destructive, `dangerInk`. The host owns the confirmation `.alert`
  /// (`!isPreset` gate mirrors the prior overflow menu — an installed gallery
  /// copy stays deletable).
  private var deleteItem: some View {
    Button(role: .destructive, action: onDelete) {
      actionColumn(
        title: String(localized: "Delete"), systemImage: "trash",
        tint: Color.dangerInk)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("scenarioDetail.deleteButton")
  }

  /// Tab-bar-style equal-width column: icon over label.
  private func actionColumn(
    title: String, systemImage: String, tint: Color
  ) -> some View {
    VStack(spacing: 4) {
      Image(systemName: systemImage)
        .font(.system(size: 20))
      Text(title)
        .font(.caption2)
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xxs)
    // Full-column hit target (the VStack alone leaves gaps between icon/label).
    .contentShape(Rectangle())
  }
}

extension View {
  /// Bottom-bar surface: iOS 26 Liquid Glass (continuity with the native tab
  /// bar this replaces), `.regularMaterial` + top hairline on iOS 18–25.
  @ViewBuilder
  fileprivate func pasturaBottomActionBarSurface() -> some View {
    if #available(iOS 26.0, *) {
      glassEffect(.regular, in: .rect)
    } else {
      background(.regularMaterial)
        .overlay(alignment: .top) { Color.rule.frame(height: 0.5) }
    }
  }
}
