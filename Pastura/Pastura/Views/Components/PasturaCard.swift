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

/// The browse-side card container: wraps arbitrary content in a white
/// (`bubbleBackground`) `.continuous` rounded rectangle with a 1pt `rule`
/// hairline border and **no shadow**, clipping content to the rounded corners.
///
/// Pastura's browse-side card form (design-system §9 "他画面への展開"),
/// distinct from the chat/promo bubble (§5.2/§5.4) which carries a left 3pt
/// moss border + soft moss shadow. Here the card reads as a quiet pane laid on
/// the warm `screenBackground` field — defined by a hairline, not lifted by
/// elevation (§1 "observation, not manipulation").
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
///     PasturaRowDivider()
///     row2
///   }
/// }
/// ```
///
/// For width: the card fills its host's width; the outer horizontal margin is
/// the caller's responsibility (apply `PasturaCardMetrics.horizontalMargin` to
/// the enclosing stack). Every browse screen uses this one `ScrollView` host
/// (#684), so the margins line up across screens by construction.
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
