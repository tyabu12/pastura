import Foundation
import Testing

@testable import Pastura

/// Unit tests for the chat-template UTF-8 validation seam in
/// ``LlamaCppService/decodeAppliedTemplate(buffer:written:)``.
///
/// The test target is the small `internal static` helper extracted from
/// ``LlamaCppService.applyChatTemplate(system:user:)`` for fault-injection
/// purposes — coercing the real `llama_chat_apply_template` C function into
/// emitting invalid UTF-8 would require a real GGUF model and a hostile
/// template fixture. The helper is pure (`(buffer, written) -> String`),
/// so we exercise the production validation path directly.
@Suite(.timeLimit(.minutes(1)))
struct LlamaCppServiceChatTemplateTests {

  // MARK: - Happy path

  @Test func validUTF8BufferReturnsDecodedString() throws {
    // "<|user|>hello<|end|>" — a plausibly-shaped (truncated) chat-template output.
    let utf8: [CChar] = [
      0x3C, 0x7C, 0x75, 0x73, 0x65, 0x72, 0x7C, 0x3E,  // "<|user|>"
      0x68, 0x65, 0x6C, 0x6C, 0x6F  // "hello"
    ]
    let result = try LlamaCppService.decodeAppliedTemplate(
      buffer: utf8, written: Int32(utf8.count))
    #expect(result == "<|user|>hello")
  }

  // MARK: - Bug fix — invalid UTF-8 must throw

  @Test func invalidUTF8BufferThrowsGenerationFailed() {
    // 0xFF is invalid as the leading byte of any UTF-8 sequence. The
    // underlying `String(llamaBuffer:length:)` returns "" in this case
    // (per its `?? ""` fallback). Pre-fix, `applyChatTemplate` propagated
    // that "" silently to the inference loop. Post-fix, the helper must
    // throw `LLMError.generationFailed` so the failure is diagnosable.
    let invalidBuffer: [CChar] = [
      CChar(bitPattern: 0x68),  // 'h'
      CChar(bitPattern: 0xFF),  // invalid UTF-8 lead byte
      CChar(bitPattern: 0x69)  // 'i'
    ]
    #expect(throws: LLMError.self) {
      _ = try LlamaCppService.decodeAppliedTemplate(
        buffer: invalidBuffer, written: 3)
    }
  }

  @Test func invalidUTF8ErrorDescriptionMentionsByteCount() {
    let invalidBuffer: [CChar] = [
      CChar(bitPattern: 0xFF),
      CChar(bitPattern: 0xFE)
    ]
    do {
      _ = try LlamaCppService.decodeAppliedTemplate(
        buffer: invalidBuffer, written: 2)
      Issue.record("expected throw, got success")
    } catch let error as LLMError {
      // Partial-match per project convention (CLAUDE.md "Error message i18n prep").
      let description = error.errorDescription ?? ""
      #expect(description.contains("invalid UTF-8"))
      #expect(description.contains("2"))
    } catch {
      Issue.record("expected LLMError, got \(error)")
    }
  }

  // MARK: - Assistant-turn prefill (#366)

  /// Helper: build a `LlamaCppService` configured purely for the chat-template
  /// path. `applyChatTemplate` does not touch the model context or sampler, so
  /// `modelPath` can be empty — no `loadModel()` is required.
  private static func makeService(assistantPrefix: String?) -> LlamaCppService {
    LlamaCppService(
      modelPath: "",
      stopSequence: "<|im_end|>",
      modelIdentifier: "ChatTemplate Test Service",
      systemPromptSuffix: nil,
      assistantPrefix: assistantPrefix
    )
  }

  /// Gemma regression pin: with `assistantPrefix == nil`, the formatted prompt
  /// must NOT carry a stray `<think>` block (i.e., behavior is byte-identical
  /// to the pre-fix output for the Gemma path). Asserting absence of `<think>`
  /// is the simplest invariant — full byte-identity is implied because the
  /// new branch only appends a string when `assistantPrefix` is non-nil.
  @Test func gemmaPathDoesNotAppendThinkBlock() throws {
    let service = Self.makeService(assistantPrefix: nil)
    let prompt = try service.applyChatTemplate(
      system: "You are a test fixture.", user: "Say hi.")
    #expect(!prompt.contains("<think>"))
    #expect(!prompt.contains("</think>"))
  }

  /// Qwen prefill: with `assistantPrefix == "<think>\n\n</think>\n\n"`, the
  /// formatted prompt must end with that exact suffix. Anchoring at the suffix
  /// catches the easy ordering regression where someone moves the append to
  /// before the chat-template marker — that would still contain the substring
  /// but break the actual Jinja-equivalent semantics.
  @Test func qwenPrefixIsAppendedAsSuffix() throws {
    let service = Self.makeService(assistantPrefix: "<think>\n\n</think>\n\n")
    let prompt = try service.applyChatTemplate(
      system: "You are a test fixture.", user: "Say hi.")
    #expect(
      prompt.hasSuffix("<think>\n\n</think>\n\n"),
      "Expected prompt to end with the prefill; got tail: \(prompt.suffix(50))"
    )
  }

  /// Cross-check: the prefill text must appear EXACTLY ONCE in the formatted
  /// prompt. If it appears twice, something duplicated it — e.g., a future
  /// regression where both the system suffix and the assistant prefix wire
  /// `<think>` content.
  @Test func qwenPrefixAppearsExactlyOnce() throws {
    let service = Self.makeService(assistantPrefix: "<think>\n\n</think>\n\n")
    let prompt = try service.applyChatTemplate(
      system: "You are a test fixture.", user: "Say hi.")
    let occurrences = prompt.components(separatedBy: "<think>").count - 1
    #expect(occurrences == 1, "Expected exactly 1 <think> occurrence, got \(occurrences)")
  }

  // MARK: - Boundary documentation (out-of-scope cases)

  /// Documents that NUL-padded output is NOT covered by the new guard.
  /// `String(bytes: [0x00, 0x00], encoding: .utf8)` returns `"\0\0"` — a
  /// non-empty string, so `decoded.isEmpty` does not fire. Issue #234 scope
  /// is the invalid-UTF-8 → empty-fallback path; an all-NUL output is a
  /// different llama.cpp bug shape that would surface downstream as a JSON
  /// parse failure on the inference output. Tracking that case is out of
  /// scope here.
  @Test func allNULBufferDoesNotThrow() throws {
    let nulBuffer: [CChar] = [0x00, 0x00, 0x00]
    let result = try LlamaCppService.decodeAppliedTemplate(
      buffer: nulBuffer, written: 3)
    // Returned as-is — the guard intentionally does not catch this.
    #expect(!result.isEmpty)
  }
}
