import SwiftUI

/// A single browse-screen row's content — optional moss leading icon, an
/// ink title, and a trailing chevron — sized to fill its width with a
/// `Rectangle` hit target.
///
/// ## Why this exists
///
/// Converting a `List`-based browse screen to `ScrollView` + ``PasturaCard``
/// (to render the grouped 1pt-`rule` card form) drops the row chrome that
/// `List` supplied for free: the disclosure chevron, the full-width tap
/// target, and the neutral (non-system-blue) label styling on
/// `NavigationLink` rows. This view restores that chrome so a row inside a
/// `PasturaCard` reads and behaves like the inset-grouped row it replaces.
///
/// It renders **content only** — wrap it at the callsite in whatever
/// triggers the action, applying `.buttonStyle(.plain)` to suppress the
/// system tint:
///
/// ```swift
/// NavigationLink(value: Route.results(scenarioId: id)) {
///   PasturaRowLabel(title: "Past Results", systemImage: "clock.arrow.circlepath")
/// }
/// .buttonStyle(.plain)
/// ```
///
/// Set `showsChevron: false` for a non-navigating row (plain info or a
/// destructive action that isn't a push).
struct PasturaRowLabel: View {
  let title: String
  var systemImage: String?
  var showsChevron: Bool

  init(title: String, systemImage: String? = nil, showsChevron: Bool = true) {
    self.title = title
    self.systemImage = systemImage
    self.showsChevron = showsChevron
  }

  var body: some View {
    HStack(spacing: 12) {
      if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(Color.moss)
      }
      Text(title)
        .foregroundStyle(Color.ink)
      Spacer(minLength: 8)
      if showsChevron {
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.muted)
      }
    }
    .padding(.horizontal, 17)
    .padding(.vertical, 15)
    .contentShape(Rectangle())
  }
}

#Preview {
  ScrollView {
    VStack(spacing: PasturaCardMetrics.interCardSpacing) {
      PasturaCard {
        VStack(spacing: 0) {
          PasturaRowLabel(title: "Run Simulation", systemImage: "play.fill")
          Divider().overlay(Color.rule)
          PasturaRowLabel(title: "Past Results", systemImage: "clock.arrow.circlepath")
        }
      }
      PasturaCard {
        PasturaRowLabel(title: "Context only — no chevron", showsChevron: false)
      }
    }
    .padding(PasturaCardMetrics.horizontalMargin)
  }
  .background(Color.screenBackground)
}
