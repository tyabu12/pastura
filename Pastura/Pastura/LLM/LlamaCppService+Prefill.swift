import Foundation
import LlamaSwift

// MARK: - Prefill

extension LlamaCppService {
  func prefill(
    context: OpaquePointer,
    tokens: [llama_token]
  ) throws {
    var mutableTokens = tokens
    var offset = 0

    while offset < mutableTokens.count {
      try Task.checkCancellation()
      let chunkSize = min(Self.batchSize, mutableTokens.count - offset)
      let batch = mutableTokens.withUnsafeMutableBufferPointer { ptr -> llama_batch in
        // baseAddress is non-nil because the while condition guarantees non-empty remaining tokens
        guard let base = ptr.baseAddress else {
          preconditionFailure("Empty token buffer should have been caught by context-size check")
        }
        return llama_batch_get_one(base + offset, Int32(chunkSize))
      }
      let decodeResult = llama_decode(context, batch)
      guard decodeResult == 0 else {
        throw LLMError.generationFailed(
          description: "llama_decode failed during prefill (error \(decodeResult))"
        )
      }
      offset += chunkSize
    }
  }
}
