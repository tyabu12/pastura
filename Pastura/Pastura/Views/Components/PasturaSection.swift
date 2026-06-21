import SwiftUI

/// A muted section header laid above a ``PasturaCard``, reproducing the
/// inset-grouped section structure that browse screens used before moving
/// to `ScrollView` + ``PasturaCard``.
///
/// Pass a `nil` title (the default) for an unheadered card — banners,
/// action groups, single-purpose cards. The header text aligns slightly
/// inset from the card edge, matching the iOS grouped-header convention.
///
/// The `style` selects the card form (see ``PasturaSectionStyle``):
/// `.insetGrouped` (default — rounded inset pane, for detail screens) or
/// `.grouped` (full-bleed band, for the browse lists; #731). The style also
/// drives the section's outer margin — `.grouped` zeroes it so the band
/// reaches the screen edges, with the header carrying its own inset.
///
/// ```swift
/// PasturaSection(String(localized: "Overview"), style: .grouped) {
///   VStack(spacing: 0) {
///     row1
///     PasturaRowDivider(leadingInset: PasturaCardMetrics.horizontalMargin)
///     row2
///   }
/// }
/// ```
struct PasturaSection<Content: View>: View {
  let title: String?
  private let style: PasturaSectionStyle
  private let content: Content

  init(
    _ title: String? = nil, style: PasturaSectionStyle = .insetGrouped,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.style = style
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let title {
        Text(title)
          .font(.subheadline)
          .foregroundStyle(Color.muted)
          .padding(.leading, headerLeadingInset)
      }
      PasturaCard(style: style) { content }
    }
    .padding(.horizontal, style.horizontalMargin)
  }

  // `.insetGrouped` already insets the whole section by `horizontalMargin`, so
  // the header nudges a further 6pt (iOS grouped-header convention). `.grouped`
  // sits edge-to-edge, so the header carries the full inset itself to align
  // with the row content.
  private var headerLeadingInset: CGFloat {
    switch style {
    case .insetGrouped: 6
    case .grouped: PasturaCardMetrics.horizontalMargin
    }
  }
}

/// A hairline divider between rows inside a ``PasturaCard``, tinted with
/// the `rule` token so multi-row grouped cards read like the inset-grouped
/// row separators they replace.
///
/// `leadingInset` defaults to 0 (full card width — detail screens). Browse
/// lists pass a positive inset so the separator starts at the row text, the
/// iOS inset-separator convention (#731).
struct PasturaRowDivider: View {
  var leadingInset: CGFloat = 0

  var body: some View {
    Rectangle()
      .fill(Color.rule)
      .frame(height: PasturaCardMetrics.borderWidth)
      .padding(.leading, leadingInset)
  }
}
