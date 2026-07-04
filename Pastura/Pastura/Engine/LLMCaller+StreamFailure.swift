import Foundation

// Stream-completion + failure-handling helpers factored out of
// `LLMCaller.call` so the core retry loop stays under SwiftLint's
// `function_body_length` budget and the file stays under `file_length`.
// `nonisolated` on the extension is required because `LLMCaller` is a
// `nonisolated` Engine type split across sibling files (a plain
// `extension` would inherit MainActor under the project's default-actor
// isolation and break the nonisolated callers in `call`).
nonisolated extension LLMCaller {
  /// Emit an `inferenceCompleted` event for `agent`, measuring elapsed
  /// wall-clock from `start`. Shared by the success and failure paths of
  /// `call` so the two otherwise-identical emits cannot drift.
  func emitInferenceCompleted(
    agent: String, since start: ContinuousClock.Instant, tokens: Int?,
    emitter: @Sendable (SimulationEvent) -> Void
  ) {
    emitter(
      .inferenceCompleted(
        agent: agent, durationSeconds: elapsedSeconds(since: start), tokenCount: tokens))
  }

  /// Whether a failed inference stream should be retried, emitting the
  /// `retryCause` diagnostic as a side effect when it should.
  ///
  /// A caught sampler crash (``LLMError/samplerCrashCaught``) is retried
  /// while budget remains. As of #907 the generation loops intercept the
  /// common case (post-object-completion continuation) as end-of-generation,
  /// so this rarely fires; it remains defense in depth for any other
  /// surfacer of the error (#885) — the trigger is sampling noise, not a
  /// deterministic per-(model, prompt, schema) defect, so a fresh inference
  /// of the same inputs usually succeeds. Every **other** throw returns
  /// `false` and keeps the immediate abort: `.suspended` is absorbed
  /// upstream in
  /// `consumeStreamWithSuspendRetry`, cancellation must propagate, and
  /// `.invalidGrammar` is a fail-fast engineering bug (its doc-comment
  /// rejects the 3× retry charade).
  func shouldRetryStreamFailure(_ error: Error, agent: String, attempt: Int) -> Bool {
    guard case LLMError.samplerCrashCaught = error, attempt < Self.maxRetries else {
      return false
    }
    emitRetryCause(agent: agent, attempt: attempt + 1, cause: "sampler_crash")
    return true
  }

  /// Wall-clock seconds elapsed since `start`, for `inferenceCompleted`
  /// duration reporting.
  func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
    let duration = ContinuousClock.now - start
    return Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
  }
}
