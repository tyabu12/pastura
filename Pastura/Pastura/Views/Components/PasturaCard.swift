import SwiftUI

/// Shared layout constants for ``PasturaCard``.
///
/// Exposed as a single source of truth so every browse-screen card
/// (`ScrollView` + `PasturaCard { ... }`) renders identical outer margins
/// and inter-card rhythm. All browse screens — Home / Shared Scenarios /
/// Past Results / Settings — share this one host (#684).
enum PasturaCardMetrics {
  /// Card corner radius — design-system §4.2 "プロモカード 14pt".
  static let cornerRadius: CGFloat = 14
  /// Hairline border width. design-system §2.2 `rule` token, 1pt.
  static let borderWidth: CGFloat = 1
  /// Outer horizontal margin from the screen edge to the card.
  static let horizontalMargin: CGFloat = 16
  /// Vertical gap between sibling cards in a `ScrollView` stack.
  static let interCardSpacing: CGFloat = 18
}

/// A `ScrollView`-friendly card container that wraps arbitrary content in
/// the ``PasturaCardSurface`` (white + 1pt `rule` border + 14pt radius,
/// no shadow) and clips content to the rounded corners.
///
/// The container adds **no internal padding** — callers control it. This
/// keeps full-bleed internal dividers possible for multi-row grouped cards
/// (e.g. ScenarioDetail "Overview" with three rows separated by 1pt `rule`
/// dividers, mirroring the iOS inset-grouped structure it replaces).
///
/// ```swift
/// PasturaCard {
///   VStack(spacing: 0) {
///     row1
///     Divider().overlay(Color.rule)
///     row2
///   }
/// }
/// ```
///
/// For width: the card fills its host's width; outer horizontal margin is
/// the caller's responsibility (apply `PasturaCardMetrics.horizontalMargin`
/// to the enclosing stack), kept symmetric with `List` row insets so the
/// Home (List) and detail (ScrollView) screens align.
struct PasturaCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: PasturaCardMetrics.cornerRadius, style: .continuous)
    content
      .background(Color.bubbleBackground)
      .clipShape(shape)
      .overlay(shape.strokeBorder(Color.rule, lineWidth: PasturaCardMetrics.borderWidth))
  }
}

#Preview {
  ScrollView {
    VStack(spacing: PasturaCardMetrics.interCardSpacing) {
      PasturaCard {
        Text("Single-line card")
          .foregroundStyle(Color.ink)
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      PasturaCard {
        VStack(spacing: 0) {
          ForEach(["Agents", "Rounds", "Est. Inferences"], id: \.self) { label in
            HStack {
              Text(label).foregroundStyle(Color.ink)
              Spacer()
              Text("2").foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            if label != "Est. Inferences" {
              Divider().overlay(Color.rule)
            }
          }
        }
      }
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
    .padding(.vertical, PasturaCardMetrics.interCardSpacing)
  }
  .background(Color.screenBackground)
}
