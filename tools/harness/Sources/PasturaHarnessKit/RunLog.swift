import Foundation

// JSONL run-log model. Execution-faithful and deliberately minimal: it
// serializes what the Engine emitted, nothing more. Judge scores / digest
// fields are Phase 2 of the scenario-factory initiative (#515) and live in
// the Phase 2 skill's own artifacts — do not add them here.

/// Terminal status of a harness run.
package enum RunStatus: String, Codable, Sendable {
  case ok
  case error
}

/// First line of a run log — static run metadata.
package struct RunStartLine: Codable, Sendable, Equatable {
  package var type = "run_start"
  package let runId: String
  /// ISO 8601 timestamp of run start.
  package let date: String
  package let scenarioId: String
  package let scenarioName: String
  /// The scenario's authoring language (`Scenario.language`).
  package let language: String
  package let model: String
  package let timeoutSec: Int
  package let estimatedInferences: Int

  package init(
    runId: String, date: String, scenarioId: String, scenarioName: String,
    language: String, model: String, timeoutSec: Int, estimatedInferences: Int
  ) {
    self.runId = runId
    self.date = date
    self.scenarioId = scenarioId
    self.scenarioName = scenarioName
    self.language = language
    self.model = model
    self.timeoutSec = timeoutSec
    self.estimatedInferences = estimatedInferences
  }
}

/// Last line of a run log — outcome summary.
package struct RunEndLine: Codable, Sendable, Equatable {
  package var type = "run_end"
  package let runId: String
  package let status: RunStatus
  /// Number of attempts consumed (1 on first-try success, 2 after the retry).
  package let attempts: Int
  package let durationSec: Double
  /// Failure description; `nil` when status is `.ok`.
  package let error: String?

  package init(
    runId: String, status: RunStatus, attempts: Int, durationSec: Double,
    error: String?
  ) {
    self.runId = runId
    self.status = status
    self.attempts = attempts
    self.durationSec = durationSec
    self.error = error
  }
}

/// One Engine event, flattened to a sparse line. Fields are optional and
/// populated per event kind; JSON encoding omits absent ones.
package struct EventLine: Codable, Sendable, Equatable {
  package var type = "event"
  /// Seconds since the current attempt started.
  package let t: Double
  /// Attempt this event belongs to (1 or 2).
  package let attempt: Int
  /// Snake-case event name (e.g. `agent_output`).
  package let event: String

  package var agent: String?
  package var round: Int?
  package var totalRounds: Int?
  package var scores: [String: Int]?
  package var phaseType: String?
  package var phasePath: [Int]?
  package var fields: [String: String]?
  package var rawText: String?
  package var value: String?
  package var votes: [String: String]?
  package var tallies: [String: Int]?
  package var agent2: String?
  package var action1: String?
  package var action2: String?
  package var voteCount: Int?
  package var condition: String?
  package var result: Bool?
  package var durationSeconds: Double?
  package var tokenCount: Int?
  package var detected: String?
  package var expected: String?
  package var error: String?
  package var relationships: [String: [String: Int]]?

  package init(
    t: Double, attempt: Int, event: String,
    agent: String? = nil, round: Int? = nil, totalRounds: Int? = nil,
    scores: [String: Int]? = nil, phaseType: String? = nil,
    phasePath: [Int]? = nil, fields: [String: String]? = nil,
    rawText: String? = nil, value: String? = nil,
    votes: [String: String]? = nil, tallies: [String: Int]? = nil,
    agent2: String? = nil, action1: String? = nil, action2: String? = nil,
    voteCount: Int? = nil, condition: String? = nil, result: Bool? = nil,
    durationSeconds: Double? = nil, tokenCount: Int? = nil,
    detected: String? = nil, expected: String? = nil, error: String? = nil,
    relationships: [String: [String: Int]]? = nil
  ) {
    self.t = t
    self.attempt = attempt
    self.event = event
    self.agent = agent
    self.round = round
    self.totalRounds = totalRounds
    self.scores = scores
    self.phaseType = phaseType
    self.phasePath = phasePath
    self.fields = fields
    self.rawText = rawText
    self.value = value
    self.votes = votes
    self.tallies = tallies
    self.agent2 = agent2
    self.action1 = action1
    self.action2 = action2
    self.voteCount = voteCount
    self.condition = condition
    self.result = result
    self.durationSeconds = durationSeconds
    self.tokenCount = tokenCount
    self.detected = detected
    self.expected = expected
    self.error = error
    self.relationships = relationships
  }
}

/// Single-line JSON encoding shared by every log line.
package enum JSONL {
  /// Deterministic (sorted keys), snake_case, single-line encoder.
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  package static func encode<T: Encodable>(_ value: T) throws -> String {
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
      throw HarnessConfigError("JSONL encoding produced non-UTF8 data")
    }
    return string
  }
}
