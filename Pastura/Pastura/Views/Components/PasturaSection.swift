import SwiftUI

/// A muted section header laid above a ``PasturaCard``, reproducing the
/// inset-grouped section structure that browse screens used before moving
/// to `ScrollView` + ``PasturaCard``.
///
/// Pass a `nil` title (the default) for an unheadered card — banners,
/// action groups, single-purpose cards. The header text aligns slightly
/// inset from the card edge, matching the iOS grouped-header convention.
///
/// ```swift
/// PasturaSection(String(localized: "Overview")) {
///   VStack(spacing: 0) {
///     row1
///     PasturaRowDivider()
///     row2
///   }
/// }
/// ```
struct PasturaSection<Content: View>: View {
  let title: String?
  private let content: Content

  init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let title {
        Text(title)
          .font(.subheadline)
          .foregroundStyle(Color.muted)
          .padding(.leading, 6)
      }
      PasturaCard { content }
    }
    .padding(.horizontal, PasturaCardMetrics.horizontalMargin)
  }
}

/// A hairline divider between rows inside a ``PasturaCard``, tinted with
/// the `rule` token so multi-row grouped cards read like the inset-grouped
/// row separators they replace.
struct PasturaRowDivider: View {
  var body: some View {
    Divider().overlay(Color.rule)
  }
}
