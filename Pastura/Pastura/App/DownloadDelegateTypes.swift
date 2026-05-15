import Foundation

// MARK: - Download Result

/// Value returned from `DownloadDelegate` to `URLSessionModelDownloader`'s
/// per-task continuation. Internal-by-default (was `private` in
/// `ModelDownloader.swift` before the file was split for `file_length` cap;
/// sibling-file access requires module-internal visibility).
struct DownloadResult: Sendable {
  let tempURL: URL
  let statusCode: Int
}

// MARK: - Per-Task State

/// State held in `DownloadDelegate.taskStates` for one in-flight task, keyed
/// by `URLSessionTask.taskIdentifier`.
///
/// PR2 unifies foreground (`download(...)` callers awaiting via
/// `CheckedContinuation`) and reattached (cross-launch BG tasks observed via
/// `AsyncStream<DownloadEvent>`) into one enum so the delegate's dispatch
/// methods can switch on the case rather than carrying two parallel maps.
enum PerTaskState: Sendable {
  /// Foreground download initiated via `URLSessionModelDownloader.download(...)`.
  /// The continuation is resumed exactly once in `didCompleteWithError`.
  case foreground(ForegroundState)
  /// Cross-launch reattach: the OS handed this task back from a prior
  /// process generation. Events are routed through the stream continuation.
  /// `stagedFileURL` is set by `didFinishDownloadingTo` and consumed by
  /// `didCompleteWithError` (success path) or by
  /// `handleReattachedStreamTermination` (consumer-drop / failure cleanup
  /// path).
  case reattached(streamContinuation: AsyncStream<DownloadEvent>.Continuation, stagedFileURL: URL?)
}

/// Inner state for `.foreground` — preserves the PR1 field layout.
struct ForegroundState: Sendable {
  let resumeOffset: Int64
  let progressHandler: @Sendable (Int64, Int64) -> Void
  let continuation: CheckedContinuation<DownloadResult, any Error>
  var downloadedFileURL: URL?
}

/// Foreground-only `didWriteData` dispatch payload. The 3-field struct
/// dodges `large_tuple` (cap = 2) while keeping the snapshot-under-lock /
/// invoke-outside-lock idiom intact. `internal` so `DownloadDelegate`
/// (sibling file) can construct it.
struct ForegroundProgressDispatch: Sendable {
  let received: Int64
  let total: Int64
  let handler: @Sendable (Int64, Int64) -> Void
}
