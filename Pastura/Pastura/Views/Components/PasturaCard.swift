import SwiftUI

/// Shared layout constants for ``PasturaCard``.
///
/// Exposed as a single source of truth so every browse-screen card
/// (`ScrollView` + `PasturaCard { ... }`) renders identical outer margins
/// and inter-card rhythm. All browse screens — Home / Shared Scenarios /
/// Past Results / Settings — share this one host (#684).
enum PasturaCardMetrics {
  /// Card corner radius for ``PasturaSectionStyle/insetGrouped`` —
  /// design-system §4.2 "プロモカード 14pt". `.grouped` squares this off.
  static let cornerRadius: CGFloat = 14
  /// Hairline border / row-divider width. design-system §2.2 `rule` token,
  /// 0.5pt (thinned from 1pt — the floating-box border read too heavy; #731).
  static let borderWidth: CGFloat = 0.5
  /// Border width for non-card surfaces that reuse the `rule` token — the
  /// SharedScenarios category-filter capsules. Held at 1pt independently of
  /// ``borderWidth`` so the card-hairline thinning doesn't drag chips down.
  static let chipBorderWidth: CGFloat = 1
  /// Outer horizontal margin from the screen edge to the card
  /// (``PasturaSectionStyle/insetGrouped`` only; `.grouped` reaches the edge).
  static let horizontalMargin: CGFloat = 16
  /// Vertical gap between sibling cards in a `ScrollView` stack.
  static let interCardSpacing: CGFloat = 18
}

/// Visual style for ``PasturaCard`` / ``PasturaSection``, mirroring Apple's
/// `UITableView.Style` / SwiftUI `ListStyle` vocabulary so the intent reads at
/// a glance to any iOS engineer.
///
/// - ``insetGrouped``: a rounded white pane inset from the screen edge with an
///   all-around hairline. The detail-screen / content-grouping form
///   (ScenarioDetail, GalleryScenarioDetail) — the default.
/// - ``grouped``: a full-bleed white band reaching both screen edges, no corner
///   radius, top + bottom hairlines only. The browse-list form (Home / Shared
///   Scenarios / Past Results / Settings; #731).
///
/// The full-bleed zero-overrides live here, NOT on ``PasturaCardMetrics`` — the
/// shared constants stay positive so a refactor can't silently collapse the
/// inset rhythm (and `PasturaCardTests.layoutSpacingIsPositive` stays honest).
enum PasturaSectionStyle {
  case insetGrouped
  case grouped

  /// Outer horizontal margin from the screen edge to the card. Zero for
  /// `.grouped` (the band reaches the edges); the shared positive constant
  /// for `.insetGrouped`.
  var horizontalMargin: CGFloat {
    switch self {
    case .insetGrouped: PasturaCardMetrics.horizontalMargin
    case .grouped: 0
    }
  }

  /// Card corner radius — the shared 14pt for `.insetGrouped`, squared off
  /// for the full-bleed `.grouped` band.
  var cornerRadius: CGFloat {
    switch self {
    case .insetGrouped: PasturaCardMetrics.cornerRadius
    case .grouped: 0
    }
  }
}

/// The browse-side card container: wraps arbitrary content in a white
/// (`bubbleBackground`) surface with a `rule` hairline and **no shadow**.
///
/// Two forms, selected by ``PasturaSectionStyle``:
/// - `.insetGrouped` — a `.continuous` rounded rectangle clipped + stroked on
///   all four sides (the chat/promo bubble of §5.2/§5.4 is a separate form with
///   a left moss border + shadow; this is the quiet browse pane of §5.9).
/// - `.grouped` — a full-bleed band: white fill reaching both screen edges with
///   top + bottom hairlines only, no radius, no side border. Against the warm
///   `screenBackground` field (only ~2% lighter than white) those two hairlines
///   are load-bearing — they, not elevation, define the band's edges (§1
///   "observation, not manipulation").
///
/// The container adds **no internal padding** — callers control it. This keeps
/// internal dividers possible for multi-row grouped cards (e.g. ScenarioDetail
/// "Overview" with three rows separated by ``PasturaRowDivider``).
///
/// ```swift
/// PasturaCard(style: .grouped) {
///   VStack(spacing: 0) {
///     row1
///     PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
///     row2
///   }
/// }
/// ```
///
/// For width: the card fills its host's width; the outer horizontal margin is
/// applied by ``PasturaSection`` from the style. Every browse screen uses this
/// one `ScrollView` host (#684), so margins line up across screens.
struct PasturaCard<Content: View>: View {
  private let style: PasturaSectionStyle
  private let content: Content

  init(style: PasturaSectionStyle = .insetGrouped, @ViewBuilder content: () -> Content) {
    self.style = style
    self.content = content()
  }

  var body: some View {
    switch style {
    case .insetGrouped: insetGroupedBody
    case .grouped: groupedBody
    }
  }

  private var insetGroupedBody: some View {
    let shape = RoundedRectangle(cornerRadius: PasturaCardMetrics.cornerRadius, style: .continuous)
    return
      content
      .background(Color.bubbleBackground)
      .clipShape(shape)
      .overlay(shape.strokeBorder(Color.rule, lineWidth: PasturaCardMetrics.borderWidth))
  }

  private var groupedBody: some View {
    content
      .frame(maxWidth: .infinity)
      .background(Color.bubbleBackground)
      // Full-bleed band: only the top + bottom hairlines define the edges
      // against the ~2%-lighter cream field (no side border, no radius).
      .overlay(alignment: .top) { hairline }
      .overlay(alignment: .bottom) { hairline }
  }

  private var hairline: some View {
    Rectangle()
      .fill(Color.rule)
      .frame(height: PasturaCardMetrics.borderWidth)
  }
}

#Preview {
  ScrollView {
    VStack(spacing: PasturaCardMetrics.interCardSpacing) {
      PasturaCard {
        Text("Inset-grouped card")
          .foregroundStyle(Color.ink)
          .padding(16)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, PasturaCardMetrics.horizontalMargin)

      PasturaCard(style: .grouped) {
        VStack(spacing: 0) {
          ForEach(["Agents", "Rounds", "Est. Inferences"], id: \.self) { label in
            HStack {
              Text(label).foregroundStyle(Color.ink)
              Spacer()
              Text("2").foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            if label != "Est. Inferences" {
              PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
            }
          }
        }
      }
    }
    .padding(.vertical, PasturaCardMetrics.interCardSpacing)
  }
  .background(Color.screenBackground)
}
