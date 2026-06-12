import Foundation
import Synchronization

/// Sink for JSONL log lines. Implementations must be safe to call from
/// concurrent task-group children.
package protocol RunLogWriting: Sendable {
  /// Appends one line (without trailing newline; the writer adds it).
  func append(_ line: String) throws
}

/// Appends lines to a file, creating parent directories on first use.
package final class FileRunLogWriter: RunLogWriting {
  private let handle: Mutex<FileHandle>

  package init(path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    self.handle = Mutex(handle)
  }

  package func append(_ line: String) throws {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    try handle.withLock { try $0.write(contentsOf: data) }
  }

  deinit {
    handle.withLock { try? $0.close() }
  }
}
