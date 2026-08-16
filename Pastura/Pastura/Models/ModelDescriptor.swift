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
  ///
  /// Includes the quantization tag (e.g., `(Q4_K_M)`) as the canonical
  /// internal identifier. UI surfaces that should hide quantization
  /// detail prefer `shortDisplayName` when non-nil.
  public let displayName: String

  /// Optional shorter UI label that omits the quantization tag
  /// (e.g., `"Gemma 4 E2B"` vs. `"Gemma 4 E2B (Q4_K_M)"`).
  ///
  /// `nil` means "fall back to `displayName`". Used by the first-launch
  /// model picker and any UI following the design-system principle of
  /// not exposing the quantization format on this surface (the user is
  /// choosing a model, not a build variant).
  public let shortDisplayName: String?

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

  /// Plaintext stop sentinel — the literal text that ends generation early when
  /// the model writes it out as ordinary text (a hallucinated turn boundary).
  ///
  /// Contract for consumers: match this against **decoded text only**. It is
  /// not the tokenizer's end-of-turn token, and a backend must not treat it as
  /// the thing that terminates a normal turn. Mechanism, and why a control
  /// token can never reach the match under llama.cpp:
  /// `LlamaCppService.stopSequence`.
  ///
  /// `"<|im_end|>"` for ChatML models such as Qwen 3; Gemma 4 carries that same string
  /// (#1417). It diverges from ``turnMarkers`` deliberately — see there.
  public let stopSequence: String

  /// This model's plaintext turn-boundary sentinels, consumed by parser-side
  /// hallucinated-turn truncation and by the chat-template leakage diagnostic.
  ///
  /// **Deliberately no default**: an inherited wrong pair fails in silence — the
  /// mechanisms keyed on it simply stop firing, with nothing to observe (#1422).
  /// `docs/models/onboarding.md` carries the collection step.
  ///
  /// For Gemma 4 this and ``stopSequence`` **disagree** on purpose: repointing the
  /// generation-side sentinel would newly *activate* a behaviour on an assumption rather
  /// than a demonstration, so it is deferred to #1451.
  /// `ModelRegistryTurnMarkerDivergenceTests` pins the divergence so a silent
  /// "consistency fix" reddens.
  public let turnMarkers: ChatTurnMarkers

  /// Minimum physical RAM required to load and run the model (bytes).
  public let minRAM: UInt64

  /// HuggingFace model page or equivalent documentation URL.
  public let modelInfoURL: URL

  /// Optional suffix appended to the system prompt for models that require it
  /// (e.g., `"/no_think"` for Qwen thinking-mode suppression). `nil` for models
  /// that need no suffix.
  public let systemPromptSuffix: String?

  /// Optional text appended to the formatted prompt *after* the chat template's
  /// assistant-role marker (i.e., prefilled into the assistant turn).
  ///
  /// Used by Qwen 3 to disable thinking mode via the official
  /// `"<think>\n\n</think>\n\n"` prefill — equivalent to what the Jinja chat
  /// template would emit under `enable_thinking=false`. llama.cpp's C-API
  /// `llama_chat_apply_template` is the simplified non-Jinja implementation and
  /// does not perform this prefill automatically, so we append it post-template.
  ///
  /// Without this prefill, Qwen 3 emits `<think>` (token 151667) as its first
  /// generated token, which the GBNF grammar's `root` rule cannot accept —
  /// `llama_grammar_accept_token` throws `std::runtime_error: Unexpected empty
  /// grammar stack`, crashing the process via an uncaught C++ exception
  /// (Issue #366).
  ///
  /// `nil` for models that need no prefill (Gemma 4 E2B).
  public let assistantPrefix: String?

  /// User-facing tagline shown in the model picker — a single short sentence
  /// describing the model's character. Never an **absolute** size; the picker
  /// row already renders that as meta. A **relative** one ("older and larger")
  /// only where the comparand is on screen beside it, which means **on a
  /// replaced descriptor, never on its replacement**: `ModelManager`'s
  /// `visibleCatalog` hides a replaced entry once it is not the active model
  /// and its state is exactly `.notDownloaded`, so a fresh install sees the
  /// replacement alone and a size claim there has nothing to compare against.
  /// Empty string when the descriptor was
  /// constructed without picker UI in mind (test fixtures, future
  /// descriptors not yet surfaced in the picker). UI sites must hide the
  /// row when empty rather than render a blank line.
  public let tagline: String

  /// The id of an older catalog entry this descriptor takes over from, under
  /// the ADD-and-keep shape (`ModelRegistry` § "ADD-and-keep"). `nil` — the
  /// default — for a descriptor that replaces nothing.
  ///
  /// This is a **catalog-topology** field, not a runtime one: nothing in the
  /// LLM layer reads it, and it is deliberately absent from the harness
  /// `ModelProfile` mirror, which carries prompt-format and integrity fields.
  /// Two app-layer mechanisms consume it, and they fail *identically and
  /// silently* if it names an id that is not in the catalog — the replaced
  /// entry simply never hides, and its recommendation never resolves forward,
  /// which looks exactly like the feature not having been written.
  /// `ModelRegistryTests.everyReplacesModelIDResolves` is the guard.
  ///
  /// The replaced entry stays in the catalog. Read `ModelRegistry`
  /// § "ADD-and-keep" before repurposing this field as a removal marker — it
  /// carries the consumers that depend on the old id's catalog membership.
  public let replacesModelID: ModelID?

  /// Returns `true` iff `name` matches `^[A-Za-z0-9._-]+\.gguf$`.
  ///
  /// Use this to validate a candidate filename before constructing a `ModelDescriptor`.
  public static func isValidFileName(_ name: String) -> Bool {
    let pattern = #"^[A-Za-z0-9._-]+\.gguf$"#
    return name.range(of: pattern, options: .regularExpression) != nil
  }

  /// Creates a new `ModelDescriptor` with all fields.
  ///
  /// `shortDisplayName` and `tagline` are defaulted so historical test
  /// fixtures don't need to thread them through; production descriptors
  /// in `ModelRegistry` set them explicitly for picker UI.
  ///
  /// - Precondition: `fileName` must match `^[A-Za-z0-9._-]+\.gguf$`.
  public init(
    id: ModelID,
    displayName: String,
    shortDisplayName: String? = nil,
    vendor: String,
    vendorURL: URL,
    downloadURL: URL,
    fileName: String,
    fileSize: Int64,
    sha256: String,
    stopSequence: String,
    turnMarkers: ChatTurnMarkers,
    minRAM: UInt64,
    modelInfoURL: URL,
    systemPromptSuffix: String?,
    assistantPrefix: String? = nil,
    tagline: String = "",
    replacesModelID: ModelID? = nil
  ) {
    precondition(
      Self.isValidFileName(fileName),
      "ModelDescriptor.fileName must match ^[A-Za-z0-9._-]+\\.gguf$ (got: \(fileName))"
    )
    self.id = id
    self.displayName = displayName
    self.shortDisplayName = shortDisplayName
    self.vendor = vendor
    self.vendorURL = vendorURL
    self.downloadURL = downloadURL
    self.fileName = fileName
    self.fileSize = fileSize
    self.sha256 = sha256
    self.stopSequence = stopSequence
    self.turnMarkers = turnMarkers
    self.minRAM = minRAM
    self.modelInfoURL = modelInfoURL
    self.systemPromptSuffix = systemPromptSuffix
    self.assistantPrefix = assistantPrefix
    self.tagline = tagline
    self.replacesModelID = replacesModelID
  }
}

// `ModelDescriptor.id: ModelID` already provides the natural identity, so the
// conformance is a marker. Required for SwiftUI APIs like
// `.fullScreenCover(item:)` that want `Identifiable` items.
extension ModelDescriptor: Identifiable {}
