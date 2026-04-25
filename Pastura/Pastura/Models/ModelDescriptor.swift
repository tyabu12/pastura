import Foundation

/// Stable string identifier for an on-device LLM model (e.g., `"gemma-4-e2b-q4-k-m"`).
public typealias ModelID = String

/// Immutable descriptor for an on-device LLM model (download URL, integrity metadata,
/// prompt-format hints). Used by `ModelManager` and `LlamaCppService` to parameterize
/// per-model behavior. Held in a static catalog (`ModelRegistry`) — not persisted.
nonisolated public struct ModelDescriptor: Sendable, Hashable {
  /// Stable identifier for the model (e.g., `"gemma-4-e2b-q4-k-m"`).
  public let id: ModelID

  /// Human-readable name shown in the UI (e.g., `"Gemma 4 E2B (Q4_K_M)"`).
  public let displayName: String

  /// Model publisher name (e.g., `"Google"`, `"Alibaba"`).
  public let vendor: String

  /// Vendor's website URL.
  public let vendorURL: URL

  /// Direct download URL for the GGUF model file.
  public let downloadURL: URL

  /// On-disk filename (e.g., `"gemma-4-E2B-it-Q4_K_M.gguf"`).
  ///
  /// Must match `^[A-Za-z0-9._-]+\.gguf$`. Validated at init time via `precondition`.
  public let fileName: String

  /// Expected file size in bytes, used to verify download completeness.
  public let fileSize: Int64

  /// Lowercase hex SHA-256 digest for integrity verification after download.
  public let sha256: String

  /// Generation stop sentinel appended by the model's tokenizer
  /// (e.g., `"<|im_end|>"` for Gemma/Llama chat format).
  public let stopSequence: String

  /// Minimum physical RAM required to load and run the model (bytes).
  public let minRAM: UInt64

  /// HuggingFace model page or equivalent documentation URL.
  public let modelInfoURL: URL

  /// Optional suffix appended to the system prompt for models that require it
  /// (e.g., `"/no_think"` for Qwen thinking-mode suppression). `nil` for models
  /// that need no suffix.
  public let systemPromptSuffix: String?

  /// Returns `true` iff `name` matches `^[A-Za-z0-9._-]+\.gguf$`.
  ///
  /// Use this to validate a candidate filename before constructing a `ModelDescriptor`.
  public static func isValidFileName(_ name: String) -> Bool {
    let pattern = #"^[A-Za-z0-9._-]+\.gguf$"#
    return name.range(of: pattern, options: .regularExpression) != nil
  }

  /// Creates a new `ModelDescriptor` with all fields.
  ///
  /// - Precondition: `fileName` must match `^[A-Za-z0-9._-]+\.gguf$`.
  public init(
    id: ModelID,
    displayName: String,
    vendor: String,
    vendorURL: URL,
    downloadURL: URL,
    fileName: String,
    fileSize: Int64,
    sha256: String,
    stopSequence: String,
    minRAM: UInt64,
    modelInfoURL: URL,
    systemPromptSuffix: String?
  ) {
    precondition(
      Self.isValidFileName(fileName),
      "ModelDescriptor.fileName must match ^[A-Za-z0-9._-]+\\.gguf$ (got: \(fileName))"
    )
    self.id = id
    self.displayName = displayName
    self.vendor = vendor
    self.vendorURL = vendorURL
    self.downloadURL = downloadURL
    self.fileName = fileName
    self.fileSize = fileSize
    self.sha256 = sha256
    self.stopSequence = stopSequence
    self.minRAM = minRAM
    self.modelInfoURL = modelInfoURL
    self.systemPromptSuffix = systemPromptSuffix
  }
}

// `ModelDescriptor.id: ModelID` already provides the natural identity, so the
// conformance is a marker. Required for SwiftUI APIs like
// `.fullScreenCover(item:)` that want `Identifiable` items.
extension ModelDescriptor: Identifiable {}
