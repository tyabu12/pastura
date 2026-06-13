import SwiftUI

/// Shared layout constants for ``PasturaCard`` / ``PasturaCardSurface``.
///
/// Exposed as a single source of truth so the two card hosts —
/// `ScrollView` containers (`PasturaCard { ... }`) and `List` rows
/// (`.listRowBackground(PasturaCardSurface())` + matching insets) — render
/// identical outer margins and inter-card rhythm. Without a shared anchor,
/// List's row insets and a hand-rolled VStack spacing drift apart (the
/// Home-on-List vs siblings-on-ScrollView consistency risk).
enum PasturaCardMetrics {
  /// Card corner radius — design-system §4.2 "プロモカード 14pt".
  static let cornerRadius: CGFloat = 14
  /// Hairline border width. design-system §2.2 `rule` token, 1pt.
  static let borderWidth: CGFloat = 1
  /// Outer horizontal margin from the screen edge to the card.
  static let horizontalMargin: CGFloat = 16
  /// Vertical gap between sibling cards in a `ScrollView` stack, and the
  /// target row spacing for `List` hosts.
  static let interCardSpacing: CGFloat = 18
}

/// The flat card surface: a white (`bubbleBackground`) rounded rectangle
/// with a 1pt `rule` hairline border and **no shadow**.
///
/// Pastura's browse-side card form (design-system §9 "他画面への展開"),
/// distinct from the chat/promo bubble (§5.2/§5.4) which carries a left
/// 3pt moss border + soft moss shadow. Here the card reads as a quiet
/// pane laid on the warm `screenBackground` field — defined by a hairline,
/// not lifted by elevation. The "observation, not manipulation" voice
/// (§1) argues against the z-axis cue a shadow implies for a list of
/// repeated cards.
///
/// Use standalone as a `List` row background:
///
/// ```swift
/// .listRowBackground(PasturaCardSurface())
/// ```
///
/// or via the ``PasturaCard`` container in a `ScrollView`.
struct PasturaCardSurface: View {
  var body: some View {
    let shape = RoundedRectangle(
      cornerRadius: PasturaCardMetrics.cornerRadius, style: .continuous)
    shape
      .fill(Color.bubbleBackground)
      .overlay(shape.strokeBorder(Color.rule, lineWidth: PasturaCardMetrics.borderWidth))
  }
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
