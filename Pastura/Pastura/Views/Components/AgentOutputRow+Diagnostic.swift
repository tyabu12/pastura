#if DEBUG

  import Foundation
  import os

  /// DEBUG-only diagnostic helpers for #133 PR#4 (streaming display
  /// redesign). Isolated so the surface is easy to remove / revisit once
  /// PR#5 ADR chooses a pivot path.
  ///
  /// Emissions feed the `StreamingDiag` category under `com.pastura` —
  /// see `SimulationViewModel.streamingDiagLogger`. Filter Console.app with
  /// `subsystem:com.pastura category:StreamingDiag` during device-run
  /// sessions.
  extension AgentOutputRow {
    /// Emit a lifecycle breadcrumb for Hyp B (LazyVStack `@State` recycle).
    /// A second `onAppear` with a different `debugInstanceID` for the same
    /// `debugRowID` indicates the row was torn down and rebuilt — and a
    /// non-zero `visibleChars` prior to that re-appear that resets to 0 is
    /// the observable symptom.
    func logDebugLifecycle(event: String) {
      let streaming = streamingPrimary != nil || streamingThought != nil
      SimulationViewModel.streamingDiagLogger.info(
        "\(event, privacy: .public) rowID=\(self.debugRowID ?? "nil", privacy: .public) agent=\(self.agent, privacy: .public) phase=\(self.phaseType.rawValue, privacy: .public) visibleChars=\(self.visibleChars) target=\(self.targetLength) streaming=\(streaming) instance=\(self.debugInstanceID.uuidString, privacy: .public)"
      )
    }

    /// Emit on every streaming-growth notification, before the gate in
    /// `handleStreamTargetChange`. `taskNil=true` or `taskCancelled=true`
    /// during an active stream flags the cancel-race surface PR#147 +
    /// PR#150 targeted; shouldn't reproduce in this PR's device runs, but
    /// the signal stays visible if it does.
    func logStreamTargetChange(newTarget: Int) {
      SimulationViewModel.streamingDiagLogger.info(
        "streamTargetChange rowID=\(self.debugRowID ?? "nil", privacy: .public) agent=\(self.agent, privacy: .public) visibleChars=\(self.visibleChars) newTarget=\(newTarget) taskNil=\(self.animationTask == nil) taskCancelled=\(self.animationTask?.isCancelled == true)"
      )
    }
  }

#endif
