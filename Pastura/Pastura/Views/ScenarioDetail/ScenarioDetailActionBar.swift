import SwiftUI

/// Bottom contextual action bar for ``ScenarioDetailView`` — replaces the tab
/// bar on the scenario-detail screen (ADR-016 § Amendment / contextual bottom
/// action bar). Two **detached** rounded-capsule elements (icon over label):
/// a **Run** capsule (the emphasized primary — emphasis comes from its
/// detachment + moss-coloured content, on a plain Liquid Glass background) and
/// a separate capsule grouping the secondary **Copy & Edit** / **Delete**
/// actions.
///
/// Why custom (not a native `.bottomBar`): iOS 26's `.bottomBar` renders
/// **icon-only** (the design language moved from text to symbols) and offers no
/// icon-over-label form — that vertical layout is a `TabView` construct. To
/// keep visible text labels *and* the Liquid Glass continuity with the native
/// tab bar it replaces, this applies `glassEffect` (iOS 26+) to custom
/// capsules, with a `.regularMaterial` (or soft-tint) fallback on iOS 18–25.
///
/// Colours carry the design-system §5.8 intent: Run = `mossDark` (primary),
/// Edit / Copy & Edit = `ink` (secondary), Delete = `dangerInk` (destructive).
///
/// The glass rendering is **real-device QA** — the simulator mis-renders iOS 26
/// bottom chrome (`swiftui-traps.md` § "iOS 26 Liquid Glass toolbar capsule") —
/// as is the `InFlightSimulationIndicator` pill's clearance above this bar.
struct ScenarioDetailActionBar: View {
  let scenarioId: String
  let scenarioName: String
  let canRun: Bool
  /// Backs Copy & Edit / Edit / Delete. `nil` during the brief load window
  /// renders Run only.
  let record: ScenarioRecord?
  let isGallerySourced: Bool
  /// Triggers the host's delete-confirmation `.alert`.
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: Spacing.s) {
      runCapsule
      if let record {
        secondaryGroup(record: record)
      }
    }
    // Inset from the screen edges + float above the bottom so the capsules read
    // as the same detached rounded shape the native iOS 26 tab bar uses on Home.
    .padding(.horizontal, Spacing.l)
    .padding(.bottom, Spacing.xs)
  }

  /// Primary — a **separate** capsule (plain Liquid Glass; moss-coloured
  /// content) so Run reads as the emphasized action, distinct from the
  /// secondary group, without a tinted background that could read as a pressed
  /// state. Tap-driven `NavigationLink` (navigation.md); `initialName` feeds
  /// SimulationView's title from the first frame (identity-neutral via
  /// `RouteHint`, ADR-008).
  private var runCapsule: some View {
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
    .frame(maxWidth: .infinity)
    .pasturaActionCapsule()
  }

  /// Secondary actions in their own neutral glass capsule.
  private func secondaryGroup(record: ScenarioRecord) -> some View {
    HStack(spacing: 0) {
      editOrCopyItem(record: record)
      if !record.isPreset {
        deleteItem
      }
    }
    .frame(maxWidth: .infinity)
    .pasturaActionCapsule()
  }

  /// Read-only sources (preset / installed gallery copy) get **Copy & Edit**
  /// (clone as an editable copy); user scenarios edit directly.
  @ViewBuilder
  private func editOrCopyItem(record: ScenarioRecord) -> some View {
    if record.isPreset || isGallerySourced {
      NavigationLink(value: Route.editor(templateYAML: record.yamlDefinition)) {
        actionColumn(
          title: String(localized: "Copy & Edit"), systemImage: "doc.on.doc",
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

  /// Tab-bar-style column: icon over label, filling its capsule's width.
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
    .padding(.vertical, Spacing.s)
    // Full-column hit target (the VStack alone leaves gaps between icon/label).
    .contentShape(Rectangle())
  }
}

extension View {
  /// Rounded **capsule** surface matching the native iOS 26 floating tab bar:
  /// plain Liquid Glass on iOS 26, `.regularMaterial` Capsule on iOS 18–25.
  /// (No tint — a coloured background read as a pressed state on device.)
  @ViewBuilder
  fileprivate func pasturaActionCapsule() -> some View {
    if #available(iOS 26.0, *) {
      glassEffect(.regular, in: .capsule)
    } else {
      background(.regularMaterial, in: Capsule())
    }
  }
}
