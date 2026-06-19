import Foundation
import Testing

@testable import Pastura

/// Unit tests for the Past Results (観察履歴) date-bucketing logic
/// (Home redesign P5). Asserts logic properties only, never rendered output
/// (ADR-009 / `.claude/rules/view-testing.md`).
///
/// The bucket **key** is the deterministic, locale-independent anchor — the
/// **title** for relative buckets ("Today"/"This Week"/"This Month") resolves
/// against the *device* locale via `String(localized:)`, so those assertions
/// only check non-emptiness. Month-heading titles are driven by the injected
/// calendar's locale (pinned to `en_US_POSIX` here), so they are asserted
/// exactly.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ResultsRowFormatTests {

  /// Fixed calendar so day/week/month boundaries are deterministic across CI
  /// locales/timezones — the helper's behavior must not depend on the runner's
  /// ambient `Calendar.current`.
  private func fixedCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
  }

  private func date(
    _ cal: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0
  ) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  // now = 2026-06-17 (Wed) 12:00 UTC. With en_US_POSIX (firstWeekday = Sunday),
  // the containing week is Sun 2026-06-14 … Sat 2026-06-20.

  @Test func sameCalendarDayIsToday() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    let bucket = ResultsRowFormat.dateBucket(
      for: date(cal, 2026, 6, 17, 9), now: now, calendar: cal)
    #expect(bucket.key == "today")
    #expect(!bucket.title.isEmpty)
  }

  @Test func earlierThisWeekIsWeek() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    #expect(
      ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 15), now: now, calendar: cal).key
        == "week")
    #expect(
      ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 14), now: now, calendar: cal).key
        == "week")
  }

  @Test func sameWeekDaysShareOneKey() {
    // Multi-page merge contract: two runs in the same week (but on different
    // days) must map to the SAME stable key so they coalesce into one section
    // even when fetched across page boundaries.
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    let first = ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 15), now: now, calendar: cal)
    let second = ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 16), now: now, calendar: cal)
    #expect(first.key == second.key)
    #expect(first.title == second.title)
  }

  @Test func earlierThisMonthDifferentWeekIsMonth() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    // 2026-06-03 is in the week Sun 2026-05-31 … Sat 2026-06-06 — a different
    // week from now, but the same month.
    let bucket = ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 3), now: now, calendar: cal)
    #expect(bucket.key == "month")
  }

  @Test func priorMonthSameYearUsesYearMonthKey() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    let bucket = ResultsRowFormat.dateBucket(for: date(cal, 2026, 5, 20), now: now, calendar: cal)
    #expect(bucket.key == "ym-2026-5")
    // Same-year month heading omits the year (en_US_POSIX → "May").
    #expect(bucket.title == "May")
  }

  @Test func priorYearUsesYearMonthKeyAndYearedTitle() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    let bucket = ResultsRowFormat.dateBucket(for: date(cal, 2025, 11, 10), now: now, calendar: cal)
    #expect(bucket.key == "ym-2025-11")
    // Prior-year heading carries the year (en_US_POSIX → "November 2025").
    #expect(bucket.title.contains("November"))
    #expect(bucket.title.contains("2025"))
  }

  @Test func priorMonthsInSameMonthShareKey() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    let first = ResultsRowFormat.dateBucket(for: date(cal, 2026, 5, 2), now: now, calendar: cal)
    let second = ResultsRowFormat.dateBucket(for: date(cal, 2026, 5, 28), now: now, calendar: cal)
    #expect(first.key == "ym-2026-5")
    #expect(second.key == "ym-2026-5")
  }

  @Test func bucketKeyMatchesFullBucketKey() {
    // The cheap key-only path (used per-run for grouping) must agree with the
    // full `dateBucket` key (used once per section for the title).
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17)
    for sample in [date(cal, 2026, 6, 17), date(cal, 2026, 6, 15), date(cal, 2026, 5, 20)] {
      #expect(
        ResultsRowFormat.bucketKey(for: sample, now: now, calendar: cal)
          == ResultsRowFormat.dateBucket(for: sample, now: now, calendar: cal).key)
    }
  }

  @Test func dayBoundaryStraddleSeparatesTodayFromWeek() {
    // A run at 23:59 "yesterday" must not collapse into "today" when now is
    // just past midnight — the day boundary, not a 24h window, defines Today.
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 0, 30)
    let yesterdayLate = date(cal, 2026, 6, 16, 23, 59)
    #expect(
      ResultsRowFormat.dateBucket(for: yesterdayLate, now: now, calendar: cal).key == "week")
    #expect(
      ResultsRowFormat.dateBucket(for: date(cal, 2026, 6, 17, 0, 5), now: now, calendar: cal).key
        == "today")
  }
}
