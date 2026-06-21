import Foundation

@testable import Pastura

// Shared fixtures for `ResultsViewModelTests` and its `+Pagination` sibling —
// a deterministic clock/calendar so date bucketing is reproducible, plus a
// fetchAll-counting repository wrapper for the #678 index-reuse regression.

/// Deterministic calendar for date bucketing — UTC + `en_US_POSIX` so
/// day/week/month boundaries don't depend on the CI runner's locale/timezone.
let resultsTestCalendar: Calendar = {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = TimeZone(identifier: "UTC")!
  cal.locale = Locale(identifier: "en_US_POSIX")
  return cal
}()

/// Fixed "now" for the suite — Wed 2026-06-17 12:00 UTC (week Sun 06-14 … Sat 06-20).
let resultsTestNow: Date = resultsTestCalendar.date(
  from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))!

/// A timestamp inside "today" relative to ``resultsTestNow``.
let resultsTestToday: Date = resultsTestCalendar.date(
  from: DateComponents(year: 2026, month: 6, day: 17, hour: 9))!

/// Builds a fixed UTC noon `Date` for a given y/m/d — for seeding runs into a
/// specific date bucket.
func resultsTestDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
  resultsTestCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

/// Wraps a real ``ScenarioRepository`` and counts
/// ``ScenarioRepository/fetchAllSummaries()`` calls so the #678 regression can
/// assert the scenario index is built once, not rebuilt per filter keystroke.
/// `nonisolated` + `@unchecked Sendable`
/// with an `NSLock`-guarded counter because repository methods run off the
/// main actor (`ResultsViewModel.offMain`) and the protocol is `Sendable`.
nonisolated final class CountingScenarioRepository: ScenarioRepository, @unchecked Sendable {
  private let wrapped: any ScenarioRepository
  private let lock = NSLock()
  private var _fetchAllCount = 0

  /// Counts the index-rebuild fetches (`fetchAllSummaries`) — the
  /// scenario-index load `ResultsViewModel` issues per window reset.
  var fetchAllCount: Int { lock.withLock { _fetchAllCount } }

  init(wrapping: any ScenarioRepository) { self.wrapped = wrapping }

  func fetchAllSummaries() throws -> [ScenarioSummary] {
    lock.withLock { _fetchAllCount += 1 }
    return try wrapped.fetchAllSummaries()
  }

  func save(_ record: ScenarioRecord) throws { try wrapped.save(record) }
  func fetchById(_ id: String) throws -> ScenarioRecord? { try wrapped.fetchById(id) }
  func fetchBySource(type: String, id: String) throws -> ScenarioRecord? {
    try wrapped.fetchBySource(type: type, id: id)
  }
  func fetchBySourceType(_ type: String) throws -> [ScenarioRecord] {
    try wrapped.fetchBySourceType(type)
  }
  func fetchByIds(_ ids: [String]) throws -> [ScenarioRecord] { try wrapped.fetchByIds(ids) }
  func fetchPresets() throws -> [ScenarioRecord] { try wrapped.fetchPresets() }
  func delete(_ id: String) throws { try wrapped.delete(id) }
}
