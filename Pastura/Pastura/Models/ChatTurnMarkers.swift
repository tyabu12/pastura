/// The turn-boundary sentinels a model's chat template writes around one turn,
/// **as plaintext**.
///
/// ### Contract for consumers
///
/// Match these against **decoded text only**; never as the thing that terminates a
/// normal turn. Under llama.cpp a genuine CONTROL token decodes to the empty string
/// (`llama_token_to_piece(..., special: false)`) and an end-of-generation token returns
/// before its piece is appended — so a marker reaches a text match only when the model
/// **hallucinates it as ordinary characters**.
///
/// ### Why per-model
///
/// The values are tokenizer-specific with no cross-family convention: ChatML (Qwen 3)
/// uses `<|im_start|>` / `<|im_end|>`, while Gemma 4 uses `<|turn>` / `<turn|>` and
/// carries neither ChatML string in its 262,144-token vocabulary. Hardcoding the ChatML
/// pair — as this project did until #1422 — leaves every mechanism keyed on it silently
/// inert for the default shipped model.
nonisolated public struct ChatTurnMarkers: Sendable, Hashable {
  /// Plaintext sentinel that opens a turn (e.g. `"<|im_start|>"`).
  ///
  /// Position decides: one after the response's first structural `{` is a hallucinated next
  /// turn, while a *leading* one is the model echoing its own template header with the
  /// payload still behind it — see `JSONResponseParser.truncateAtTurnMarkers`.
  public let start: String

  /// Plaintext sentinel that closes a turn (e.g. `"<|im_end|>"`).
  ///
  /// Unlike ``start``, an occurrence *anywhere* is a turn boundary: everything after it
  /// belongs to a turn that is not this one.
  public let end: String

  /// Creates a marker pair.
  ///
  /// - Parameters:
  ///   - start: Plaintext turn-open sentinel.
  ///   - end: Plaintext turn-close sentinel.
  public init(start: String, end: String) {
    self.start = start
    self.end = end
  }

  /// The ChatML pair (`<|im_start|>` / `<|im_end|>`) — Qwen 3 and the wider ChatML family.
  ///
  /// Also the baseline every consumer keeps in its effective set, so backends with no
  /// descriptor to consult (Ollama, `MockLLMService`, FoundationModels) keep pre-#1422
  /// behaviour.
  public static let chatML = ChatTurnMarkers(start: "<|im_start|>", end: "<|im_end|>")
}
