import Foundation
import os

// MARK: - Thermal Throttle

extension LlamaCppService {
  /// Pauses briefly when device is overheating (ADR-002 §5).
  /// Uses `try await` (not `try?`) so Task cancellation propagates through the sleep.
  func throttleIfOverheating() async throws {
    let thermalState = ProcessInfo.processInfo.thermalState
    if thermalState == .serious || thermalState == .critical {
      logger.warning("Thermal state \(String(describing: thermalState)) — inserting 200ms pause")
      try await Task.sleep(for: .milliseconds(200))
    }
  }
}
