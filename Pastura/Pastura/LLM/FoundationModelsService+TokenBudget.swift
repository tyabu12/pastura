// Sibling-file split of ``FoundationModelsService``'s token-budget
// instrumentation (#1154), extracted when the primary file crossed swiftlint's
// 400-line `file_length` limit.
//
// Three wrappers are all required and each fails differently if omitted:
//   - `#if canImport(FoundationModels)` — matches the primary file's SDK gate.
//   - `@available(iOS 26, macOS 26, *)`  — the extended type carries it.
//   - `nonisolated` on the EXTENSION    — under SWIFT_DEFAULT_ACTOR_ISOLATION
//     = MainActor a plain extension inherits MainActor, and the diagnostic
//     fires at the CALLSITE in `generate`, not here
//     (.claude/rules/swift-isolation.md Pattern 3).
#if canImport(FoundationModels)

  import Foundation
  import FoundationModels
  import os

  @available(iOS 26, macOS 26, *)
  nonisolated extension FoundationModelsService {

    static let tokenBudgetLogger = Logger(
      subsystem: "app.pastura.Pastura", category: "FMTokenBudget")

    /// Emits one diagnostic line to OSLog and mirrors it to stderr.
    ///
    /// The stderr mirror is what the macOS harness (ADR-013) actually reads —
    /// CLI `os.Logger` output is not reliably queryable via `log show`, and
    /// `run_scenario.sh` captures stderr to `<out>.stderr.log`. That file is
    /// already mixed-content and every consumer parses it with
    /// `jq -Rc 'fromjson? | select(...)'`, which silently drops non-JSON lines,
    /// so a plain-text line here cannot corrupt the `DiagLine` JSONL channel.
    ///
    /// Every value on these lines is a token count or a fixed marker — never
    /// scenario text or model output — so `privacy: .public` is correct here
    /// (CLAUDE.md "Logger privacy").
    static func emitTokenBudget(_ line: String) {
      tokenBudgetLogger.info("\(line, privacy: .public)")
      fputs("\(line)\n", stderr)
    }

    /// Measures what the turn's INPUT costs against the context window, before
    /// generation runs (#1154 blocker 2).
    ///
    /// `contextSize` is the denominator and is emitted unconditionally: it is
    /// available at 26.0, and blocker 2's headline "4k" figure is itself a claim
    /// worth measuring rather than inheriting. The SDK back-deploys a constant
    /// below 26.4, so a ≥26.4 runtime may legitimately report a different size.
    ///
    /// - Note: `Instructions(system)` is load-bearing. `String` conforms to BOTH
    ///   `PromptRepresentable` and `InstructionsRepresentable`, so passing the
    ///   bare `String` silently binds the `some PromptRepresentable` overload
    ///   and measures the system prompt under *prompt* framing — the emitted
    ///   `instructions=` value would be quietly mislabelled.
    /// - Returns: The turn's total input tokens, or `-1` when unmeasurable. The
    ///   caller threads this into ``logResponseTokenBudget(seq:inputTokens:entries:)``
    ///   so occupancy can be summed — the response side cannot recover it, see
    ///   that method's note on `transcriptEntries`.
    @discardableResult
    func logInputTokenBudget(
      seq: Int, system: String, user: String, schema: GenerationSchema?
    ) async -> Int {
      let contextSize = model.contextSize
      guard #available(iOS 26.4, macOS 26.4, *) else {
        // Explicit rather than a silent skip: for an instrument, "no output" and
        // "nothing to report" are otherwise indistinguishable.
        Self.emitTokenBudget(
          "fmTokenBudget seq=\(seq) phase=input contextSize=\(contextSize) "
            + "note=instrumentation-unavailable-runtime-below-26.4")
        return -1
      }
      // Every count is `try?` with a -1 sentinel. `tokenCount` is `async throws`,
      // and a propagating instrumentation error would leave `generate` as a
      // generation failure, reach `LLMCaller`, and be counted as a turn skip
      // against ADR-021's 3-consecutive-skip breaker — instrumentation
      // manufacturing the very failures it exists to measure.
      let instructions = (try? await model.tokenCount(for: Instructions(system))) ?? -1
      let prompt = (try? await model.tokenCount(for: user)) ?? -1
      var schemaTokens = -1
      if let schema {
        schemaTokens = (try? await model.tokenCount(for: schema)) ?? -1
      }
      // Summed here so the response side can report occupancy. `schemaTokens` is
      // excluded: `includeSchemaInPrompt` is false, so the schema constrains
      // decoding without entering the prompt — counting it would inflate input.
      let inputTokens =
        instructions >= 0 && prompt >= 0 ? instructions + prompt : -1
      Self.emitTokenBudget(
        "fmTokenBudget seq=\(seq) phase=input contextSize=\(contextSize) "
          + "instructions=\(instructions) prompt=\(prompt) schema=\(schemaTokens) "
          + "input=\(inputTokens)")
      return inputTokens
    }

    /// Measures what the completed turn OCCUPIES in the context window.
    ///
    /// Takes the transcript slice rather than the `Response` so both the plain
    /// and the guided path (whose `Content` differs) can call it unchanged, and
    /// takes `inputTokens` from the input-side pass because the response cannot
    /// recover it — see the `transcript` note below.
    func logResponseTokenBudget(
      seq: Int, inputTokens: Int, entries: ArraySlice<Transcript.Entry>
    ) async {
      // No unavailable-note here, unlike the input side: that pass already
      // marked this turn, and a second identical line per turn would just
      // inflate the log.
      guard #available(iOS 26.4, macOS 26.4, *) else { return }
      let contextSize = model.contextSize
      let responseEntries = entries.filter {
        if case .response = $0 { return true } else { return false }
      }
      let responseTokens = (try? await model.tokenCount(for: responseEntries)) ?? -1
      // MEASURED, not assumed: on macOS 26.5 this equals `responseTokens` in
      // every observed turn — 79 of 79 across the #1154 smoke runs, holding in
      // the plain, guided, and capped arms alike — i.e.
      // `Response.transcriptEntries` carries ONLY the response entry — the
      // `.response` filter above is a no-op and this is NOT a full-conversation
      // occupancy figure. It is kept as a tripwire: if a future SDK starts
      // including the prompt entry, the two terms diverge in the log and the
      // occupancy arithmetic below has to be revisited rather than silently
      // double-counting.
      let transcriptTokens = (try? await model.tokenCount(for: entries)) ?? -1
      // Occupancy is therefore input + response, NOT the transcript count.
      // Both terms are tokenized as separate fragments, so neither includes the
      // session's own role/turn framing: this SUM IS A LOWER BOUND on true
      // occupancy, and `headroom` correspondingly an UPPER bound.
      let occupancy =
        inputTokens >= 0 && responseTokens >= 0 ? inputTokens + responseTokens : -1
      // Rendered as text, NOT as a -1 sentinel like its neighbours: headroom is
      // a derived value that goes legitimately negative once occupancy exceeds
      // the window, so `occupancy == contextSize + 1` would print `headroom=-1`
      // and read as "unmeasurable". That collision would land exactly on the
      // overshoot case this instrumentation exists to catch.
      let headroom = occupancy >= 0 ? String(contextSize - occupancy) : "unmeasured"
      // ADVISORY, not exact. `responseTokens` counts a `Transcript.Entry`, which
      // carries role/segment framing, while `maximumResponseTokens` bounds the
      // generator's raw output — so near the cap this biases toward FALSE
      // POSITIVES by the framing delta. Read it as "probably truncated" and
      // confirm against the raw `responseTokens` / `cap` on the same line.
      let cap = maximumResponseTokens
      let hitCap = cap.map { responseTokens >= $0 } ?? false
      Self.emitTokenBudget(
        "fmTokenBudget seq=\(seq) phase=response contextSize=\(contextSize) "
          + "input=\(inputTokens) response=\(responseTokens) transcript=\(transcriptTokens) "
          + "occupancy=\(occupancy) headroom=\(headroom) "
          + "cap=\(cap.map(String.init) ?? "none") hitCap=\(hitCap)")
    }
  }

#endif
