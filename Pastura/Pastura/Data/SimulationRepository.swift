import Foundation
import GRDB

/// Repository for persisting and retrieving simulation records.
nonisolated public protocol SimulationRepository: Sendable {
  /// Saves a simulation record (full-row upsert).
  /// Inserts if new; replaces **all** columns if the ID already exists.
  func save(_ record: SimulationRecord) throws

  /// Fetches a simulation by its unique ID. Returns `nil` if not found.
  func fetchById(_ id: String) throws -> SimulationRecord?

  /// Fetches all simulations for a given scenario.
  func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord]

  /// Fetches a page of past runs across **all** scenarios, newest-first, as
  /// lightweight ``PastRunListItem`` projections — each run's full `stateJSON`
  /// is decoded only to extract the top-3 scores and is then discarded, so it
  /// never accumulates in app memory (the #586 memory fix).
  ///
  /// Keyset pagination: pass the previous page's last item as `before` (nil
  /// for the first page); the next page returns rows strictly older than the
  /// cursor on the composite `(createdAt DESC, id DESC)` order. This is stable
  /// under concurrent inserts at the top of the stream, unlike `LIMIT/OFFSET`.
  ///
  /// When `nameQuery` is non-nil and non-blank the page is narrowed to runs
  /// whose scenario name (live runs) or ``SimulationRecord/scenarioNameSnapshot``
  /// (orphaned runs) contains the query as a case-insensitive substring.
  ///
  /// - Returns: up to `limit` items. A returned count equal to `limit`
  ///   indicates more pages may exist.
  func fetchRecentRunPage(
    nameQuery: String?, before: SimulationPageCursor?, limit: Int
  ) throws -> [PastRunListItem]

  /// Fetches **all** runs for a single scenario, newest-first, as lightweight
  /// ``PastRunListItem`` projections (the per-scenario Detail entry-point —
  /// not paginated). Shares the `stateJSON`-projecting path with
  /// ``fetchRecentRunPage(nameQuery:before:limit:)``.
  func fetchRunList(scenarioId: String) throws -> [PastRunListItem]

  /// Fetches all "orphaned" simulations — runs whose source scenario was
  /// deleted, leaving `scenarioId` NULL (the FK is `ON DELETE SET NULL`
  /// since v7). Their display data lives in the `scenario*Snapshot` columns.
  /// Ordered newest-first.
  func fetchOrphaned() throws -> [SimulationRecord]

  /// Fetches all simulations with the given status, ordered newest-first.
  ///
  /// Used by the Home redesign's resume-from-paused surface (ADR-016 P3),
  /// which queries `.paused` runs; the P3 resume logic itself is not wired
  /// here.
  func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord]

  /// Returns the number of **completed** runs per scenario, keyed by the
  /// run's `scenarioId`, computed as a `GROUP BY` aggregate (not a
  /// fetch-all-then-count). Orphaned runs (`scenarioId IS NULL`, the
  /// `ON DELETE SET NULL` outcome since v7) are excluded — a null key is
  /// meaningless for a per-scenario count.
  ///
  /// Powers the Home row "観察回数" (ADR-016). The App layer aggregates the
  /// returned per-variant counts across ADR-010 D6 language variants by
  /// `sourceId`, so this method intentionally keys by the concrete variant's
  /// `scenarioId` and leaves the cross-variant rollup to the consumer.
  func completedRunCountsByScenarioId() throws -> [String: Int]

  /// Returns the number of **completed** runs across all scenarios, as a
  /// `COUNT(*)` aggregate. Orphaned runs (`scenarioId` NULL) are included —
  /// unlike ``completedRunCountsByScenarioId()``, this is not scoped per
  /// scenario, so there is no null-key row to drop.
  func completedRunCount(excludingRunId: String?) throws -> Int

  /// Updates state-related fields (stateJSON, currentRound, currentPhaseIndex)
  /// without touching other columns. Used for pause/resume.
  ///
  /// - Throws: `DataError.recordNotFound` if no record with the given ID exists.
  func updateState(
    _ id: String, stateJSON: String,
    currentRound: Int, currentPhaseIndex: Int
  ) throws

  /// Updates only the status field.
  ///
  /// - Throws: `DataError.recordNotFound` if no record with the given ID exists.
  func updateStatus(_ id: String, status: SimulationStatus) throws

  /// Updates only the `degradedTurnCount` field (ADR-021 D6). Called at run
  /// completion to record how many LLM turns degraded to a skip. Additive to
  /// the status write — the taxonomy is unchanged; this is a quality
  /// annotation surfaced as a Results/History badge.
  ///
  /// - Throws: `DataError.recordNotFound` if no record with the given ID exists.
  func updateDegradedTurnCount(_ id: String, count: Int) throws

  /// Returns the total number of runs matching the same name filter used by
  /// ``fetchRecentRunPage(nameQuery:before:limit:)`` — but with no keyset
  /// cursor and no row limit. Powers the Past Results screen-title subtitle
  /// "N 回の記録" (Home redesign P5).
  ///
  /// Every run visible in the P5 date-grouped History list is shown (no
  /// dangling-drop), so this count is intended to equal the number of rows
  /// the list renders for the same filter. Orphaned runs (scenarioId NULL)
  /// are **included** in the unfiltered total because they appear in the list.
  ///
  /// - Parameter nameQuery: Optional substring. nil or blank → unfiltered.
  ///   Non-blank → case-insensitive LIKE match on the live scenario name or
  ///   the run's ``SimulationRecord/scenarioNameSnapshot``.
  func totalRunCount(nameQuery: String?) throws -> Int

  /// Deletes a simulation by ID. No-op if the record does not exist.
  func delete(_ id: String) throws

  /// Deletes **all** simulation runs and reclaims freed disk pages.
  ///
  /// Child `turns` / `code_phase_events` rows cascade away via their
  /// `ON DELETE CASCADE` foreign keys. A post-purge `VACUUM` reclaims
  /// the freed pages (ADR-015 §4.1 — opt-in, post-purge only; the
  /// per-run ``delete(_:)`` deliberately skips `VACUUM`).
  func deleteAll() throws

  /// Returns the byte size of the **past-results** content only — the
  /// `simulations`, `turns`, and `code_phase_events` tables — by summing
  /// the UTF-8 length of their substantial TEXT columns.
  ///
  /// Deliberately **excludes** the `scenarios` table (bundled presets are
  /// re-seeded on every launch and survive a clear-all), the SQLite schema
  /// / index / free pages, and the rollback journal. So this is NOT the
  /// database file size (`page_count * page_size`): it is what "Clear all
  /// results" actually reclaims, and it reaches exactly `0` once every run
  /// is deleted — matching the Settings "Past Results" caption's intent
  /// (#770). It reads off a single connection, so it works for in-memory
  /// databases (tests) as well as the on-disk store — no file-path
  /// dependency, keeping the measure inside the Data layer.
  ///
  /// The sum covers the JSON-payload + snapshot columns that dominate
  /// per-run storage (ADR-015 §2); id / FK / integer / timestamp / short
  /// label columns are omitted as byte-negligible next to the payloads.
  ///
  /// Powers the App layer's advisory growth cap (ADR-015 D1 / §3) — a
  /// non-deleting safety stop surfaced when the store grows large.
  func pastResultsByteCount() throws -> Int64
}

/// GRDB-backed implementation of `SimulationRepository`.
nonisolated public final class GRDBSimulationRepository: SimulationRepository, Sendable {
  // `internal` (not `private`): read by the `pastResultsByteCount()` impl
  // in the sibling `SimulationRepository+PastResultsSize.swift` extension,
  // which a cross-file extension can only reach at module scope.
  let dbWriter: any DatabaseWriter

  public init(dbWriter: any DatabaseWriter) {
    self.dbWriter = dbWriter
  }

  public func save(_ record: SimulationRecord) throws {
    try dbWriter.write { db in
      let mutable = record
      try mutable.save(db)
    }
  }

  public func fetchById(_ id: String) throws -> SimulationRecord? {
    try dbWriter.read { db in
      try SimulationRecord.fetchOne(db, key: id)
    }
  }

  public func fetchByScenarioId(_ scenarioId: String) throws -> [SimulationRecord] {
    try dbWriter.read { db in
      try SimulationRecord
        .filter(Column("scenarioId") == scenarioId)
        .order(Column("createdAt").desc)
        .fetchAll(db)
    }
  }

  public func fetchRecentRunPage(
    nameQuery: String?, before: SimulationPageCursor?, limit: Int
  ) throws -> [PastRunListItem] {
    try dbWriter.read { db in
      var conditions: [String] = []
      var arguments: [DatabaseValueConvertible] = []

      // Name filter — push the substring match into SQL so it can surface
      // runs that are not yet on a loaded page. Live runs match the joined
      // scenario name; orphaned runs match their captured snapshot. Relies on
      // SQLite's default ASCII-only case-folding for `LIKE` (adequate for the
      // ja/en scope: ja has no case; en folds). `%`/`_` in the user query are
      // escaped so they are matched literally, not as wildcards.
      let trimmed = nameQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasFilter = !(trimmed ?? "").isEmpty
      if hasFilter, let trimmed {
        let pattern = "%" + Self.escapeLikePattern(trimmed) + "%"
        conditions.append(
          #"(sc.name LIKE ? ESCAPE '\' OR sim.scenarioNameSnapshot LIKE ? ESCAPE '\')"#)
        arguments.append(pattern)
        arguments.append(pattern)
      }

      // Keyset (seek) predicate — strictly older than the cursor on the
      // composite `(createdAt DESC, id DESC)` order. `createdAt` is stored as
      // a fixed-width millisecond TEXT (GRDB default), so the `id` tie-break
      // is load-bearing whenever two runs collapse to the same millisecond.
      if let cursor = before {
        conditions.append(
          "(sim.createdAt < ? OR (sim.createdAt = ? AND sim.id < ?))")
        arguments.append(cursor.createdAt)
        arguments.append(cursor.createdAt)
        arguments.append(cursor.id)
      }

      let joinClause = hasFilter ? "LEFT JOIN scenarios sc ON sim.scenarioId = sc.id" : ""
      let whereClause =
        conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
      // `arguments` is bound positionally, so its append order must mirror the
      // `?` order in the SQL: filter pattern ×2 → cursor ×3 → LIMIT. Any new
      // condition added above must keep `LIMIT` appended last.
      arguments.append(limit)

      let sql = """
        SELECT sim.* FROM simulations sim
        \(joinClause)
        \(whereClause)
        ORDER BY sim.createdAt DESC, sim.id DESC
        LIMIT ?
        """

      let cursor = try SimulationRecord.fetchCursor(
        db, sql: sql, arguments: StatementArguments(arguments))
      var items: [PastRunListItem] = []
      // Iterate one record at a time so the heavy `stateJSON` of the current
      // row is the only one resident — it is projected to top-3 scores and the
      // record is then released before the next is read.
      while let record = try cursor.next() {
        items.append(Self.projectListItem(from: record))
      }
      return items
    }
  }

  public func fetchRunList(scenarioId: String) throws -> [PastRunListItem] {
    try dbWriter.read { db in
      let cursor = try SimulationRecord.fetchCursor(
        db,
        sql: """
          SELECT * FROM simulations
          WHERE scenarioId = ?
          ORDER BY createdAt DESC, id DESC
          """,
        arguments: [scenarioId])
      var items: [PastRunListItem] = []
      while let record = try cursor.next() {
        items.append(Self.projectListItem(from: record))
      }
      return items
    }
  }

  /// Projects a full record to its lightweight list shape, decoding only the
  /// `scores` map out of `stateJSON` (the heavy `conversationLog` etc. are
  /// never materialized). Top scores are highest-first, capped at three, with
  /// agent name as a deterministic tie-break so the chip order is stable.
  private static func projectListItem(from record: SimulationRecord) -> PastRunListItem {
    PastRunListItem(
      id: record.id,
      scenarioId: record.scenarioId,
      createdAt: record.createdAt,
      status: record.status,
      currentRound: record.currentRound,
      scenarioNameSnapshot: record.scenarioNameSnapshot,
      scenarioYamlSnapshot: record.scenarioYamlSnapshot,
      scenarioCategorySnapshot: record.scenarioCategorySnapshot,
      topScores: topScores(fromStateJSON: record.stateJSON),
      degradedTurnCount: record.degradedTurnCount)
  }

  /// A minimal decodable view over `stateJSON` — only `scores` is read, so
  /// decoding stays cheap and never holds the full `SimulationState`.
  private struct ScoresProjection: Decodable {
    let scores: [String: Int]
  }

  private static func topScores(fromStateJSON json: String) -> [PastRunScore] {
    guard let data = json.data(using: .utf8),
      let parsed = try? JSONDecoder().decode(ScoresProjection.self, from: data)
    else { return [] }
    return parsed.scores
      .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
      .prefix(3)
      .map { PastRunScore(name: $0.key, value: $0.value) }
  }

  /// Escapes `LIKE` metacharacters so a user's filter text matches literally.
  /// Backslash first (it is the `ESCAPE` char), then `%` and `_`.
  private static func escapeLikePattern(_ raw: String) -> String {
    raw.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  public func fetchOrphaned() throws -> [SimulationRecord] {
    try dbWriter.read { db in
      // `== nil` compiles to `IS NULL` in GRDB.
      try SimulationRecord
        .filter(Column("scenarioId") == nil)
        .order(Column("createdAt").desc)
        .fetchAll(db)
    }
  }

  public func fetchByStatus(_ status: SimulationStatus) throws -> [SimulationRecord] {
    try dbWriter.read { db in
      try SimulationRecord
        .filter(Column("status") == status.rawValue)
        .order(Column("createdAt").desc)
        .fetchAll(db)
    }
  }

  public func completedRunCountsByScenarioId() throws -> [String: Int] {
    try dbWriter.read { db in
      // GROUP BY aggregate so the count is computed SQL-side. `scenarioId IS
      // NOT NULL` drops orphaned runs; a null group key can't map onto a row.
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT scenarioId, COUNT(*) AS cnt
          FROM simulations
          WHERE status = ? AND scenarioId IS NOT NULL
          GROUP BY scenarioId
          """,
        arguments: [SimulationStatus.completed.rawValue])
      var result: [String: Int] = [:]
      for row in rows {
        // scenarioId is non-null by the WHERE clause; skip defensively if not.
        guard let scenarioId: String = row["scenarioId"] else { continue }
        result[scenarioId] = row["cnt"]
      }
      return result
    }
  }

  // `updateState`, `updateStatus`, `updateDegradedTurnCount` (single-column
  // read-modify-write mutators) live in `SimulationRepository+Mutations.swift`
  // to keep this file under the file_length cap.

  public func totalRunCount(nameQuery: String?) throws -> Int {
    try dbWriter.read { db in
      // Mirror fetchRecentRunPage's name-filter logic exactly so this count
      // equals the number of rows the P5 date-grouped History list renders for
      // the same query (parity rationale: every run is shown in the list —
      // no dangling-drop — so count == list row count for any given filter).
      let trimmed = nameQuery?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasFilter = !(trimmed ?? "").isEmpty

      if hasFilter, let trimmed {
        let pattern = "%" + Self.escapeLikePattern(trimmed) + "%"
        // The JOIN is required only when filtering; omitting it for the
        // unfiltered path keeps the query minimal (no unnecessary scan of
        // the scenarios table).
        return try Int.fetchOne(
          db,
          sql: #"""
            SELECT COUNT(*) FROM simulations sim
            LEFT JOIN scenarios sc ON sim.scenarioId = sc.id
            WHERE (sc.name LIKE ? ESCAPE '\' OR sim.scenarioNameSnapshot LIKE ? ESCAPE '\')
            """#,
          arguments: [pattern, pattern]) ?? 0
      } else {
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM simulations") ?? 0
      }
    }
  }

  public func delete(_ id: String) throws {
    try dbWriter.write { db in
      _ = try SimulationRecord.deleteOne(db, key: id)
    }
  }

  public func deleteAll() throws {
    // `VACUUM` cannot run inside a transaction (SQLite), so use
    // `writeWithoutTransaction`. The `ON DELETE CASCADE` FKs on
    // `turns` / `code_phase_events` still fire under the enabled
    // `foreignKeysEnabled` config, so the bulk delete cascades.
    try dbWriter.writeWithoutTransaction { db in
      _ = try SimulationRecord.deleteAll(db)
      try db.execute(sql: "VACUUM")
    }
  }
}
