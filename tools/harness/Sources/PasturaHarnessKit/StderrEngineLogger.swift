import Foundation
import PasturaCore
import Synchronization

/// One Engine diagnostic, rendered as a single JSONL record.
///
/// Deliberately NOT part of the `RunLog` JSONL schema: `RunLog.swift` is
/// "execution-faithful and deliberately minimal — it serializes what the
/// Engine emitted, nothing more". Diagnostics are a *second* channel with a
/// different lifetime, so they go to stderr and stay out of the run log the
/// judge/digest tooling reads.
package struct DiagLine: Codable, Sendable, Equatable {
  /// Schema discriminator — a constant, never set per-record.
  package let type = "diag"
  /// Monotonic within one process, starting at 1. The join key: the Engine
  /// runs phases sequentially, so `seq` order IS execution order.
  package let seq: Int
  /// The enclosing `HarnessRunner` attempt (1 or 2). Without this, a scenario
  /// that fails attempt 1 and reruns double-counts every diagnostic with no
  /// way to split the two passes apart.
  package let attempt: Int
  package let level: String
  package let category: String
  package let message: String

  package init(seq: Int, attempt: Int, level: String, category: String, message: String) {
    self.seq = seq
    self.attempt = attempt
    self.level = level
    self.category = category
    self.message = message
  }
}

/// An ``EngineLogger`` that writes one JSON record per line to stderr.
///
/// ## Why this exists
///
/// The harness previously left `SimulationRunner`'s `logger:` at its
/// `NoopEngineLogger` default, so every Engine diagnostic was discarded. That
/// is fine until a failure class needs to be *counted* rather than merely
/// survived — which is exactly the Foundation Models permissive-guardrails
/// evaluation (#1072):
///
/// - With **default** guardrails a refusal throws `guardrailViolation`, and
///   `TurnFailureGate.cause(for:)` carries the error's description verbatim
///   into the run log's `turn_skipped` line. Grep-classifiable.
/// - With **permissive** guardrails that throw never happens (per Apple: the
///   session "never throws a guardrailViolation error when generating string
///   responses" — the model returns a refusal *as content* instead). The
///   refusal then fails JSON parsing and `cause(for:)` falls through to the
///   literal `"retries exhausted"` — byte-identical to an ordinary malformed
///   -JSON failure.
///
/// So the run log alone cannot tell a refusal from a parse failure, and an
/// A/B across guardrail modes would compare a labelled arm against an
/// unlabelled one. `LLMCaller.logParseFailure` already hands the raw model
/// output to this seam; capturing it is what makes the refusal classifiable.
/// Classification stays *post-hoc* and evidence-bearing (the raw text is in
/// the record) rather than being asserted by a locale-fragile prefix match
/// inside a production service.
///
/// - Note: `LLMCaller` truncates the captured output at `raw.prefix(500)`, so
///   a long response arrives clipped — read a mid-token ending as truncation,
///   not as the model stopping there. A refusal is short enough to survive.
///
/// ## Reading the output
///
/// `run_scenario.sh` already redirects stderr to `${OUT%.jsonl}.stderr.log`.
/// One record per line — `message` is JSON-escaped, so a multi-line model
/// output cannot smear one diagnostic across many lines and inflate a
/// `grep -c`.
///
/// ## Counting rule (load-bearing)
///
/// **Never count these records.** One logical failure appears up to
/// `LLMCaller.maxRetries + 1` times (the retry loop logs every failed
/// attempt), and a `HarnessRunner` rerun replays the lot — so a `grep -c` over
/// this channel over-counts by an unstable factor. The tally lives in the run
/// log; these records only answer **why**. What duplicates is the evidence,
/// never the tally.
///
/// The tally is NOT simply `count(turn_skipped)`. Two carve-outs, both of
/// which bite the #1072 battery:
///
/// 1. **The breaker's tripping turn is never logged.** `TurnFailureGate` throws
///    `turnFailureLimitReached` at the 3rd *consecutive* skip and returns
///    before `emitter(.turnSkipped(...))`, so that turn produces evidence here
///    but no tally line. A run whose `run_end` carries that error therefore
///    has `count(turn_skipped) + 1` failures — and it is **truncated**, so its
///    refusal *rate* is a lower bound, not a rate. (The counter resets on every
///    success, so the tally is not capped at 2: #1072's word_wolf-ja logged 9
///    skips before three landed back-to-back.)
/// 2. **`narrate` is outside the tally entirely.** `NarrateHandler` degrades by
///    omission and deliberately bypasses the gate — no `.turnSkipped`, no
///    breaker increment (#909) — yet it drives its own `LLMCaller`, so a
///    narrator refusal DOES appear here. `word_wolf.yaml` / `word_wolf_en.yaml`
///    both carry a `narrate` phase, so 2 of the 6 battery cells will show
///    narrator evidence with no matching tally line. Count `agent=` narrator
///    records separately; do not fold them into the agent-turn rate.
///
/// Both guardrail arms ARE gate-degradable, so their tallies are comparable:
/// `FoundationModelsService.map` turns `guardrailViolation` into
/// `LLMError.generationFailed`, which `streamFailureError` wraps as
/// `SimulationError.llmGenerationFailed` — one of the two cases
/// `TurnFailureGate.isTurnDegradable` accepts.
///
/// ## Attribution
///
/// Records self-attribute: `LLMCaller`'s parse-failure line carries
/// `agent=…`. Do NOT try to recover the agent by scanning neighbouring
/// `retryCause` records — a turn's *terminal* failure emits no trailing
/// `retryCause` (`call` throws instead), so the next record on the channel
/// belongs to the next agent.
///
/// Ordering: the Engine has **no concurrency** — no `TaskGroup` / `async let`
/// anywhere under `Pastura/Pastura/Engine/` — so records arrive in execution
/// order and `seq` orders them against the run log.
package final class StderrEngineLogger: EngineLogger {
  private struct State {
    var seq = 0
    var attempt = 1
  }

  private let state = Mutex(State())
  private let sink: @Sendable (String) -> Void

  /// - Parameter sink: Where a rendered record goes. Defaults to stderr;
  ///   injectable so tests capture records without touching the process's
  ///   real file descriptors.
  package init(sink: (@Sendable (String) -> Void)? = nil) {
    self.sink =
      sink
      ?? { line in
        FileHandle.standardError.write(Data((line + "\n").utf8))
      }
  }

  /// Stamps subsequent records with the enclosing harness attempt.
  ///
  /// Called by ``HarnessRunner`` at the top of each attempt. The attempt is
  /// carried here rather than threaded through `StreamFactory` so the factory
  /// signature — and every test that injects one — stays unchanged.
  package func beginAttempt(_ attempt: Int) {
    state.withLock { $0.attempt = attempt }
  }

  package func log(
    _ level: EngineLogLevel,
    category: String,
    _ message: String,
    privacy: EngineLogPrivacy
  ) {
    // `privacy` is intentionally ignored: it governs OSLog redaction in
    // off-device TestFlight / Release captures. This logger only ever runs in
    // a local developer harness, where capturing the real content verbatim is
    // the entire point — a redacted `<private>` parse failure would defeat it.
    _ = privacy

    let (seq, attempt) = state.withLock { state -> (Int, Int) in
      state.seq += 1
      return (state.seq, state.attempt)
    }
    let line = DiagLine(
      seq: seq, attempt: attempt, level: Self.name(for: level),
      category: category, message: message)
    // A diagnostic that cannot be encoded is dropped rather than crashing the
    // run — the run log is the primary artifact; this channel is advisory.
    guard let encoded = try? JSONL.encode(line) else { return }
    sink(encoded)
  }

  /// No `default:` — a new ``EngineLogLevel`` must be named here rather than
  /// silently folding into an existing bucket and skewing a diagnostic count.
  private static func name(for level: EngineLogLevel) -> String {
    switch level {
    case .debug: return "debug"
    case .info: return "info"
    case .warning: return "warning"
    }
  }
}
