import Foundation

/// Pure display-formatting helpers for the Past Results (観察履歴) list
/// (Home redesign P5: date-grouped chronological runs).
///
/// Kept `nonisolated` and side-effect-free so the date-bucketing logic — the
/// non-trivial part the list depends on — is unit-testable without rendering
/// (ADR-009 / `.claude/rules/view-testing.md`: extract logic, never assert
/// rendered output). Mirrors `HomeScenarioRowFormat`.
nonisolated enum ResultsRowFormat {

  /// A date-grouping section for the History list.
  ///
  /// `key` is a stable, locale-independent identity used to coalesce runs into
  /// one section — load-bearing for keyset pagination, where runs of the same
  /// period arrive across multiple pages and must merge rather than spawn a
  /// duplicate section. `title` is the localized display heading, kept separate
  /// from `key` so display copy never affects section identity.
  struct DateBucket: Equatable, Sendable {
    let key: String
    let title: String
  }

  /// Buckets a run's `createdAt` relative to `now` into a date section:
  /// Today → This Week → This Month → an older "Month [Year]" heading.
  ///
  /// The ladder is checked most-recent-first, so a week that straddles a month
  /// boundary resolves to "This Week" (the finer bucket wins). Section ordering
  /// is **not** encoded here — the caller groups a newest-first run stream, so
  /// buckets surface in recency order by first appearance.
  ///
  /// - Parameters:
  ///   - calendar: Injectable so day/week/month boundaries (and the month
  ///     heading's locale) are deterministic in tests. Production passes
  ///     `Calendar.current`.
  static func dateBucket(for date: Date, now: Date, calendar: Calendar) -> DateBucket {
    if calendar.isDate(date, inSameDayAs: now) {
      return DateBucket(key: "today", title: String(localized: "Today"))
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
      return DateBucket(key: "week", title: String(localized: "This Week"))
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .month) {
      return DateBucket(key: "month", title: String(localized: "This Month"))
    }
    let comps = calendar.dateComponents([.year, .month], from: date)
    let year = comps.year ?? 0
    let month = comps.month ?? 0
    return DateBucket(
      key: "ym-\(year)-\(month)",
      title: monthHeading(for: date, now: now, calendar: calendar))
  }

  /// Localized "Month" heading for an older section — bare month name when the
  /// run is from the current year, month + year otherwise. Driven by the
  /// injected calendar's locale so it tracks the section's date context (and
  /// stays deterministic in tests) rather than relying on a per-string catalog
  /// key for every month name.
  private static func monthHeading(for date: Date, now: Date, calendar: Calendar) -> String {
    let sameYear =
      calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = calendar.locale ?? Locale.current
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMM" : "yMMMM")
    return formatter.string(from: date)
  }
}
