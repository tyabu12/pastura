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
    let key = bucketKey(for: date, now: now, calendar: calendar)
    return DateBucket(key: key, title: title(forKey: key, date: date, now: now, calendar: calendar))
  }

  /// The stable bucket key alone — cheap (calendar comparisons only, no
  /// `DateFormatter`). The caller groups a run stream by this key and resolves
  /// the display ``DateBucket/title`` once per distinct key, so the per-section
  /// month-heading formatter isn't rebuilt for every run.
  static func bucketKey(for date: Date, now: Date, calendar: Calendar) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "today" }
    if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "week" }
    if calendar.isDate(date, equalTo: now, toGranularity: .month) { return "month" }
    let comps = calendar.dateComponents([.year, .month], from: date)
    return "ym-\(comps.year ?? 0)-\(comps.month ?? 0)"
  }

  private static func title(
    forKey key: String, date: Date, now: Date, calendar: Calendar
  ) -> String {
    switch key {
    case "today": return String(localized: "Today")
    case "week": return String(localized: "This Week")
    case "month": return String(localized: "This Month")
    default: return monthHeading(for: date, now: now, calendar: calendar)
    }
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

  // MARK: - Result summary (P5 PR2)

  /// One-line, archetype-safe result summary for a History row — replaces the
  /// raw score chips (`%@ (%lld)`), which would print "0" for score-empty
  /// archetypes (werewolf / consensus, whose `state.scores` is empty). A
  /// deliberate fallback ladder that NEVER surfaces a score number for a
  /// score-empty run:
  ///
  /// 1. **paused** → "Paused at Round K / N" (N known) or "Paused at Round K"
  ///    (N unknown — orphaned / parse-failed metadata).
  /// 2. **completed with a unique top scorer** (non-empty top scores AND a
  ///    strict 1st > 2nd) → "Winner: X".
  /// 3. **completed otherwise** (empty scores OR a top-of-table tie) →
  ///    "All N rounds complete" (N known) or "Complete". No score number, so a
  ///    score-empty run can never read "0".
  /// 4. **any other status** (running / failed / cancelled / unknown) → `nil`;
  ///    the caller falls back to the status badge.
  ///
  /// - Parameters:
  ///   - topScores: the repository projection (highest-first, capped at 3), so
  ///     the unique-max test is a cheap first-vs-second comparison.
  ///   - currentRound: `K`, the round the run reached (paused branch only).
  ///   - totalRounds: `N` from the scenario definition; `nil` when unknown.
  static func resultSummary(
    status: SimulationStatus?,
    topScores: [PastRunScore],
    currentRound: Int,
    totalRounds: Int?
  ) -> String? {
    switch status {
    case .paused:
      if let totalRounds, totalRounds > 0 {
        return String(
          format: String(localized: "Paused at Round %lld / %lld"), currentRound, totalRounds)
      }
      return String(format: String(localized: "Paused at Round %lld"), currentRound)
    case .completed:
      if let winner = uniqueTopScorer(topScores) {
        return String(format: String(localized: "Winner: %@"), winner)
      }
      if let totalRounds, totalRounds > 0 {
        return String(format: String(localized: "All %lld rounds complete"), totalRounds)
      }
      return String(localized: "Complete")
    default:
      return nil
    }
  }

  /// The single highest-scoring agent's name when the top score is strictly
  /// greater than the runner-up (a unique winner — including a solo run with a
  /// single scorer). `nil` for empty scores or a top-of-table tie, which route
  /// to the completion summary instead.
  private static func uniqueTopScorer(_ topScores: [PastRunScore]) -> String? {
    guard let first = topScores.first else { return nil }
    if topScores.count == 1 { return first.name }
    return first.value > topScores[1].value ? first.name : nil
  }

  // MARK: - Sheep avatars (P5 PR2)

  /// Maximum sheep avatars drawn in one row before clamping (mirrors
  /// ``HomeScenarioRowFormat/maxRowSheep``). The exact cast size is secondary
  /// garnish the user doesn't act on in the list; VoiceOver still announces the
  /// true count via the row's `%lld agents` label.
  static let maxRowSheep = 5

  /// Number of sheep faces to draw for `agentCount`, clamped to ``maxRowSheep``.
  /// Returns 0 when the count is unknown (snapshot / live YAML parse failure)
  /// so the caller draws no faces.
  static func rowSheepCount(agentCount: Int?) -> Int {
    guard let agentCount, agentCount > 0 else { return 0 }
    return min(agentCount, maxRowSheep)
  }
}
