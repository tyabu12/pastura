import Foundation

/// The compact result label + status-color category shown in a History row's
/// trailing status pill (#747). One pill covers **every** state — it replaces
/// the former `resultSummary` text + `statusBadge` fallback pair (a completed /
/// paused run got prose, everything else a badge). The label is kept short so
/// it sits beside the scenario name without crowding it (`style` drives the pill
/// tint, mapped in `ResultsView`); it is archetype-safe and NEVER surfaces a
/// score number for a score-empty run (werewolf / consensus, whose
/// `state.scores` is empty):
///
/// 1. **completed with a unique top scorer** (strict 1st > 2nd) → "X wins".
/// 2. **completed otherwise** (empty scores OR a top-of-table tie) → "Complete".
///    No score number, so a score-empty run can never read "0".
/// 3. **paused** → "Paused K/N" (N known) or "Paused K" (N unknown).
/// 4. **running / failed / cancelled / unknown** → the bare state label.
///
/// Top-level (not nested in ``ResultsRowFormat``) to stay within SwiftLint's
/// 1-level `nesting` limit, since it carries its own nested ``Style``.
nonisolated struct ResultPill: Equatable, Sendable {
  /// Status-color category — mapped to tint tokens by the View, not here, so the
  /// App/Views color boundary stays intact (mirrors `statusBadge`'s old
  /// per-state coloring).
  enum Style: Equatable, Sendable {
    /// completed / has a winner — moss (positive).
    case completed
    /// paused — neutral ink-secondary.
    case paused
    /// running / failed / cancelled / unknown — muted.
    case pending
  }
  let label: String
  let style: Style
}

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

  // MARK: - Result pill (#747 follow-up)

  /// Builds the trailing result pill for a History row. See ``ResultPill`` for
  /// the label ladder.
  ///
  /// - Parameters:
  ///   - topScores: the repository projection (highest-first, capped at 3), so
  ///     the unique-max test is a cheap first-vs-second comparison.
  ///   - currentRound: `K`, the round the run reached (paused branch only).
  ///   - totalRounds: `N` from the scenario definition; `nil` when unknown.
  static func resultPill(
    status: SimulationStatus?,
    topScores: [PastRunScore],
    currentRound: Int,
    totalRounds: Int?
  ) -> ResultPill {
    switch status {
    case .completed:
      if let winner = uniqueTopScorer(topScores) {
        return ResultPill(
          label: String(format: String(localized: "%@ wins"), winner), style: .completed)
      }
      return ResultPill(label: String(localized: "Complete"), style: .completed)
    case .paused:
      if let totalRounds, totalRounds > 0 {
        return ResultPill(
          label: String(format: String(localized: "Paused %lld/%lld"), currentRound, totalRounds),
          style: .paused)
      }
      return ResultPill(
        label: String(format: String(localized: "Paused %lld"), currentRound), style: .paused)
    case .running:
      return ResultPill(label: String(localized: "Running"), style: .pending)
    case .failed:
      return ResultPill(label: String(localized: "Failed"), style: .pending)
    case .cancelled:
      return ResultPill(label: String(localized: "Cancelled"), style: .pending)
    case .none:
      return ResultPill(label: String(localized: "Unknown"), style: .pending)
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

  /// Maximum sheep avatars drawn in one timeline row before clamping. Each
  /// surface owns its own bound — Browse's art tile clamps to 6
  /// (``GalleryCatalogMetrics/maxClusterSheep``) because the tile has more room;
  /// Home's equivalent was retired with the shared summary row in #1296. The
  /// exact cast size is secondary garnish the user doesn't act on in the list;
  /// VoiceOver still announces the true count via the row's `%lld agents` label.
  static let maxRowSheep = 5

  /// Number of sheep faces to draw for `agentCount`, clamped to ``maxRowSheep``.
  /// Returns 0 when the count is unknown (snapshot / live YAML parse failure)
  /// so the caller draws no faces.
  static func rowSheepCount(agentCount: Int?) -> Int {
    guard let agentCount, agentCount > 0 else { return 0 }
    return min(agentCount, maxRowSheep)
  }

  // MARK: - Category caption (#748)

  /// Localized display name for a run's snapshot gallery category, or nil when
  /// the run carries no category (local / self-made / pre-v10) or the snapshot
  /// raw value no longer maps to a `GalleryCategory` case (degrade to nil
  /// rather than show a stale token). nil ⇒ the row draws no category line.
  static func categoryCaption(for categorySnapshot: String?) -> String? {
    categorySnapshot.flatMap { GalleryCategory(rawValue: $0)?.displayName }
  }

  // MARK: - Relative timestamp (#712)

  /// A relative, X / Instagram-style timestamp for a History row: "Just now" /
  /// "N minutes / hours / days ago" for recent runs, then a locale-formatted
  /// absolute date ("Jun 11" this year, "Nov 10, 2025" earlier).
  ///
  /// The tiers use **elapsed time** (`now − date`), deliberately independent of
  /// the section header's **calendar-day** bucket (Today / This Week / …) — so a
  /// run from 22:00 yesterday, read at 09:00, sits under "This Week" yet shows
  /// "11 hours ago". The two are complementary, not contradictory.
  ///
  /// English singular forms are separate keys (n == 1) so "1 hour ago" never
  /// renders as the ungrammatical "1 hours ago"; Japanese has no plural so both
  /// map to the same shape (1時間前 / N時間前). A future date (clock skew,
  /// `delta ≤ 0`) collapses to "Just now".
  ///
  /// - Parameters:
  ///   - now / calendar: injectable so the elapsed-time tiers and the
  ///     locale-driven absolute date are deterministic in tests (production
  ///     passes `Date()` / `Calendar.current`).
  static func relativeTimestamp(for date: Date, now: Date, calendar: Calendar) -> String {
    let delta = now.timeIntervalSince(date)
    if delta < 60 { return String(localized: "Just now") }
    if delta < 3600 {
      let minutes = Int(delta / 60)
      return minutes == 1
        ? String(localized: "1 minute ago")
        : String(format: String(localized: "%lld minutes ago"), minutes)
    }
    if delta < 86_400 {
      let hours = Int(delta / 3600)
      return hours == 1
        ? String(localized: "1 hour ago")
        : String(format: String(localized: "%lld hours ago"), hours)
    }
    if delta < 7 * 86_400 {
      let days = Int(delta / 86_400)
      return days == 1
        ? String(localized: "1 day ago")
        : String(format: String(localized: "%lld days ago"), days)
    }
    return absoluteDate(for: date, now: now, calendar: calendar)
  }

  /// Locale-formatted absolute date for an older run — month + day this year,
  /// month + day + year for a prior year. Mirrors ``monthHeading``'s mechanism
  /// (a `DateFormatter` keyed off the injected calendar's locale) with a day
  /// component, so the ja "6月11日" / "2025年11月10日" ordering is CLDR-driven.
  private static func absoluteDate(for date: Date, now: Date, calendar: Calendar) -> String {
    let sameYear =
      calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = calendar.locale ?? Locale.current
    // Pin the zone to the injected calendar's (not DateFormatter's default
    // `TimeZone.current`) so the rendered day/year agrees with the `sameYear`
    // extraction above for any injected calendar — full test determinism.
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
    return formatter.string(from: date)
  }
}
