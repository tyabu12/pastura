import SwiftUI

// MARK: - Action affordances (cancel link, inline retry)
//
// Lifted out of `PromoCard.swift` to keep `file_length` under swiftlint's
// 400-line cap. `PromoCard.swift` was sitting at exactly 400 lines with zero
// headroom — the next one-line addition anywhere in the file would fail
// `swiftlint lint --strict`.
extension PromoCard {

  /// Full-width "Stop download" action bar at the card's bottom edge, shown
  /// only when `onCancel` is set. Its own fixed-geometry row (not the
  /// per-progress-rebuilt meta row) keeps the hit region stable and the
  /// full-width target easy to hit. Styled as a filled footer button (a plain
  /// link didn't read as tappable on-device): `stop.fill` glyph + subtle
  /// neutral fill (`rule` @0.45, so the full-opacity `rule` top hairline stays
  /// visible) — still neutral per `design-system.md` §2.6 (never red; the fill
  /// is a low-opacity neutral, not `danger`). Text self-describes; no a11y label.
  func cancelLinkRow(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: "stop.fill")
          .font(.system(size: 10))
          .foregroundStyle(Color.inkSecondary)
        Text(String(localized: "Stop download"))
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.inkSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(Color.rule.opacity(0.45))
      .overlay(alignment: .top) {
        Rectangle()
          .fill(Color.rule)
          .frame(height: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  func retryView(message: String) -> some View {
    HStack(alignment: .center, spacing: Spacing.s) {
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "Download interrupted"))
          .textStyle(Typography.metaEta)
          .foregroundStyle(Color.metaStrongL3)
        Text(message)
          .textStyle(Typography.metaValue)
          .foregroundStyle(Color.metaBaseL3)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      Button(action: onRetry) {
        Text(String(localized: "Retry"))
          .textStyle(Typography.metaLabel)
          .foregroundStyle(Color.inkOnAccent)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            RoundedRectangle(cornerRadius: Radius.button)
              // `mossDark`, not base `moss`: `metaLabel` is 9pt, i.e. WCAG normal text.
              // `inkOnAccent` over `mossDark` is ≈4.76:1 in light and ≈7.12:1 in dark;
              // over base `moss` it is only ≈3.03:1 in light. Note it is NOT white in
              // dark — the token is paired (ADR-028 slice 4).
              .fill(Color.mossDark))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 7)
  }
}
