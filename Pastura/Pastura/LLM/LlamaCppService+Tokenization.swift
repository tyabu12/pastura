import Foundation
import LlamaSwift

// MARK: - Tokenization

extension LlamaCppService {
  func tokenize(
    vocab: OpaquePointer?,
    text: String,
    addSpecial: Bool
  ) throws -> [llama_token] {
    return try text.withCString { cStr in
      let textLen = Int32(strlen(cStr))
      let maxTokens = textLen + 128

      var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
      let nTokens = llama_tokenize(
        vocab, cStr, textLen, &tokens, maxTokens, addSpecial,
        true  // parse_special: handle special tokens in the template
      )

      if nTokens < 0 {
        // Buffer was too small; retry with the required size
        let required = -nTokens
        tokens = [llama_token](repeating: 0, count: Int(required))
        let nTokens2 = llama_tokenize(
          vocab, cStr, textLen, &tokens, required, addSpecial, true
        )
        guard nTokens2 >= 0 else {
          throw LLMError.generationFailed(description: "Tokenization failed")
        }
        return Array(tokens.prefix(Int(nTokens2)))
      }

      return Array(tokens.prefix(Int(nTokens)))
    }
  }

  /// Decodes a single token ID to its string piece.
  func decodePiece(
    vocab: OpaquePointer?,
    token: llama_token
  ) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    let nChars = llama_token_to_piece(
      vocab, token, &buffer, Int32(buffer.count), 0, false
    )
    if nChars > 0 {
      buffer[Int(nChars)] = 0  // null-terminate
      return String(cString: buffer)
    } else if nChars < 0 {
      // Buffer too small; retry with required size
      var largeBuffer = [CChar](repeating: 0, count: Int(-nChars) + 1)
      let retryChars = llama_token_to_piece(
        vocab, token, &largeBuffer, Int32(largeBuffer.count), 0, false
      )
      if retryChars > 0 {
        largeBuffer[Int(retryChars)] = 0
        return String(cString: largeBuffer)
      }
    }
    return ""
  }
}
