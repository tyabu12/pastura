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
      // Cooperative suspend, mirroring the generate loop. Prefill batches can
      // each take 200-500ms on long prompts, so a single iteration boundary
      // is enough headroom to honour a backgrounding signal.
      if suspendController?.isSuspendRequested() == true {
        throw LLMError.suspended
      }
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
        // Reactive suspend safety net — see generate() for the rationale.
        throw decodeFailureError(decodeResult)
      }
      offset += chunkSize
    }
  }
}
