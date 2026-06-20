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

  // MARK: - Result summary ladder (P5 PR2)

  private func scores(_ pairs: [(String, Int)]) -> [PastRunScore] {
    pairs.map { PastRunScore(name: $0.0, value: $0.1) }
  }

  @Test func pausedSummaryWithKnownTotalShowsBothRounds() {
    let summary = ResultsRowFormat.resultSummary(
      status: .paused, topScores: [], currentRound: 3, totalRounds: 5)
    let value = try? #require(summary)
    #expect(value?.contains("3") == true)
    #expect(value?.contains("5") == true)
  }

  @Test func pausedSummaryWithoutTotalOmitsTheTotal() {
    let summary = ResultsRowFormat.resultSummary(
      status: .paused, topScores: [], currentRound: 3, totalRounds: nil)
    let value = try? #require(summary)
    #expect(value?.contains("3") == true)
    // No "/" pair when N is unknown — the single-round form, not "Round 3 / ?".
    #expect(value?.contains("/") == false)
  }

  @Test func completedWithUniqueTopScorerShowsWinner() {
    // Repository projects highest-first; a strict 1st > 2nd is a unique winner.
    let summary = ResultsRowFormat.resultSummary(
      status: .completed, topScores: scores([("Carol", 12), ("Alice", 10), ("Bob", 8)]),
      currentRound: 5, totalRounds: 5)
    #expect(summary?.contains("Carol") == true)
  }

  @Test func completedSoloScorerCountsAsUniqueWinner() {
    // A single-agent run (one scorer) is a deliberate unique winner, not a
    // "completion" summary.
    let summary = ResultsRowFormat.resultSummary(
      status: .completed, topScores: scores([("Alice", 7)]), currentRound: 1, totalRounds: 1)
    #expect(summary?.contains("Alice") == true)
  }

  @Test func completedWithTopOfTableTieFallsBackToCompletion() {
    // Tie at the top → no unique winner → completion summary, NOT a name.
    let summary = ResultsRowFormat.resultSummary(
      status: .completed, topScores: scores([("Alice", 9), ("Bob", 9)]),
      currentRound: 5, totalRounds: 5)
    let value = try? #require(summary)
    #expect(value?.contains("Alice") == false)
    #expect(value?.contains("5") == true)
  }

  @Test func completedWithEmptyScoresNeverShowsAScore() {
    // ★ The load-bearing invariant: a score-empty archetype (werewolf /
    // consensus) must NEVER render "0". N = 5 has no "0" digit, so the absence
    // of "0" is an exact check that no score number leaked in.
    let summary = ResultsRowFormat.resultSummary(
      status: .completed, topScores: [], currentRound: 5, totalRounds: 5)
    let value = try? #require(summary)
    #expect(value?.contains("0") == false)
    #expect(value?.contains("(") == false)  // no "X (0)" chip form
    #expect(value?.contains("5") == true)  // the round count is shown
  }

  @Test func completedWithEmptyScoresAndUnknownTotalShowsBareCompletion() {
    let summary = ResultsRowFormat.resultSummary(
      status: .completed, topScores: [], currentRound: 5, totalRounds: nil)
    let value = try? #require(summary)
    #expect(value?.isEmpty == false)
    #expect(value?.contains("0") == false)
    #expect(value?.contains("(") == false)
  }

  @Test func nonPausedNonCompletedStatusesHaveNoSummary() {
    for status in [SimulationStatus.running, .failed, .cancelled] as [SimulationStatus] {
      #expect(
        ResultsRowFormat.resultSummary(
          status: status, topScores: scores([("Alice", 3)]), currentRound: 2, totalRounds: 5)
          == nil)
    }
    // Unknown status (nil) also yields no summary.
    #expect(
      ResultsRowFormat.resultSummary(
        status: nil, topScores: [], currentRound: 0, totalRounds: nil) == nil)
  }

  // MARK: - Sheep count clamping (P5 PR2)

  @Test func rowSheepCountMatchesAgentCountBelowMax() {
    #expect(ResultsRowFormat.rowSheepCount(agentCount: 1) == 1)
    #expect(ResultsRowFormat.rowSheepCount(agentCount: 4) == 4)
    #expect(
      ResultsRowFormat.rowSheepCount(agentCount: ResultsRowFormat.maxRowSheep)
        == ResultsRowFormat.maxRowSheep)
  }

  @Test func rowSheepCountClampsAboveMax() {
    #expect(
      ResultsRowFormat.rowSheepCount(agentCount: ResultsRowFormat.maxRowSheep + 1)
        == ResultsRowFormat.maxRowSheep)
    #expect(ResultsRowFormat.rowSheepCount(agentCount: 99) == ResultsRowFormat.maxRowSheep)
  }

  @Test func rowSheepCountZeroWhenUnknownOrEmpty() {
    #expect(ResultsRowFormat.rowSheepCount(agentCount: nil) == 0)
    #expect(ResultsRowFormat.rowSheepCount(agentCount: 0) == 0)
  }

  // MARK: - Relative timestamp (#712)

  /// `relativeTimestamp` for a run `secondsAgo` before `now`.
  private func rel(_ now: Date, _ secondsAgo: Double, _ cal: Calendar) -> String {
    ResultsRowFormat.relativeTimestamp(
      for: now.addingTimeInterval(-secondsAgo), now: now, calendar: cal)
  }

  // The relative-tier *copy* comes from `String(localized:)` (device locale), so
  // the exact words aren't asserted; the locale-independent numeral IS. The
  // absolute-date tier is driven by the injected en_US_POSIX calendar, so its
  // month/year ARE asserted exactly (mirrors the date-bucket tests above).

  @Test func relativeJustNowCarriesNoNumber() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    // < 60s (and the 59s edge) → "Just now" / "たった今" — no numeral.
    for secondsAgo in [0.0, 30.0, 59.0] {
      let result = rel(now, secondsAgo, cal)
      #expect(result.rangeOfCharacter(from: .decimalDigits) == nil)
    }
  }

  @Test func relativeFutureDateCollapsesToJustNow() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    // Clock skew (date after now) → "Just now", never a negative number.
    let result = ResultsRowFormat.relativeTimestamp(
      for: now.addingTimeInterval(3600), now: now, calendar: cal)
    #expect(result.rangeOfCharacter(from: .decimalDigits) == nil)
  }

  @Test func relativeMinutesTier() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    #expect(rel(now, 60, cal).contains("1"))  // 60s → singular
    #expect(rel(now, 330, cal).contains("5"))  // 5m30s → 5
    #expect(rel(now, 3599, cal).contains("59"))  // 59m59s → still minutes
  }

  @Test func relativeHoursTierStartsAtExactly3600s() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    let oneHour = rel(now, 3600, cal)  // exactly 1h → hours tier, not "59 min"
    #expect(oneHour.contains("1"))
    #expect(!oneHour.contains("59"))
    #expect(rel(now, 23 * 3600, cal).contains("23"))
  }

  @Test func relativeDaysTierStartsAtExactly24h() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    let oneDay = rel(now, 86_400, cal)  // exactly 24h → days tier, not "24 hours"
    #expect(oneDay.contains("1"))
    #expect(!oneDay.contains("24"))
    #expect(rel(now, 6 * 86_400, cal).contains("6"))
  }

  @Test func relativeTierBoundariesSelectDistinctCopy() {
    // The numeral "1" is shared by the minute/hour/day singular forms, so assert
    // the tiers pick *different* copy (locale-robust: ja 1分前/1時間前/1日前 differ).
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    #expect(rel(now, 60, cal) != rel(now, 3600, cal))
    #expect(rel(now, 3600, cal) != rel(now, 86_400, cal))
  }

  @Test func relativeSevenDaysSwitchesToAbsoluteDate() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    // Exactly 7 days → absolute date tier (en_US_POSIX MMMd → "Jun 10").
    #expect(rel(now, 7 * 86_400, cal).contains("Jun"))
  }

  @Test func relativeSameYearDateOmitsYear() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    // 14 days ago, same year → "Jun 3" (month + day, no year).
    let result = ResultsRowFormat.relativeTimestamp(
      for: date(cal, 2026, 6, 3, 12), now: now, calendar: cal)
    #expect(result.contains("Jun"))
    #expect(!result.contains("2026"))
  }

  @Test func relativePriorYearDateCarriesYear() {
    let cal = fixedCalendar()
    let now = date(cal, 2026, 6, 17, 12)
    let result = ResultsRowFormat.relativeTimestamp(
      for: date(cal, 2025, 11, 10, 12), now: now, calendar: cal)
    #expect(result.contains("Nov"))
    #expect(result.contains("2025"))
  }

  @Test func relativeCrossYearNearSevenDaysUsesPriorYearDate() {
    // 8 days ago across the year boundary → absolute date tier, prior-year form
    // (the one case where a reader might fear a 7-day/date-tier gap).
    let cal = fixedCalendar()
    let now = date(cal, 2026, 1, 3, 12)
    let result = ResultsRowFormat.relativeTimestamp(
      for: date(cal, 2025, 12, 26, 12), now: now, calendar: cal)
    #expect(result.contains("Dec"))
    #expect(result.contains("2025"))
  }
}
