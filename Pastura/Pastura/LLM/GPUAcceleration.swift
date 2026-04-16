import Foundation

/// GPU acceleration mode for on-device LLM inference.
///
/// Maps to llama.cpp's `n_gpu_layers` parameter. Used by `LlamaCppService.reloadModel`
/// to switch between GPU and CPU inference at runtime (e.g., for iOS background
/// execution where GPU access is not available on iPhone).
nonisolated public enum GPUAcceleration: Sendable {
  /// Offload all model layers to the GPU (Metal). Fastest inference path.
  case full
  /// Run inference entirely on CPU. Slower but does not require GPU access —
  /// usable in iOS background where GPU may be unavailable.
  case none

  /// The llama.cpp `n_gpu_layers` value for this mode.
  /// - `-1` = all layers on GPU
  /// - `0` = CPU only
  var nGpuLayers: Int32 {
    switch self {
    case .full: return -1
    case .none: return 0
    }
  }
}
