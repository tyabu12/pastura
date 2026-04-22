import Foundation
import LlamaSwift

// MARK: - Chat Template

extension LlamaCppService {
  func applyChatTemplate(system: String, user: String) throws -> String {
    // Append the descriptor's optional suffix to the system prompt. Used today
    // to inject `/no_think` for Qwen 3 (disables thinking mode so the model
    // emits JSON directly instead of wrapping in `<think>...</think>` blocks
    // that would starve the `maxTokens` budget before the JSON appears).
    let effectiveSystem = systemPromptSuffix.map { "\(system)\n\($0)" } ?? system

    // Build llama_chat_message array using C strings
    guard
      let systemRole = strdup("system"),
      let userRole = strdup("user"),
      let systemContent = strdup(effectiveSystem),
      let userContent = strdup(user)
    else {
      throw LLMError.generationFailed(
        description: "Memory allocation failed for chat template"
      )
    }
    defer {
      free(systemRole)
      free(userRole)
      free(systemContent)
      free(userContent)
    }

    var messages: [llama_chat_message] = [
      llama_chat_message(role: systemRole, content: systemContent),
      llama_chat_message(role: userRole, content: userContent)
    ]

    // First call: determine required buffer size
    let requiredSize = llama_chat_apply_template(
      nil, &messages, messages.count, true, nil, 0
    )
    guard requiredSize > 0 else {
      throw LLMError.generationFailed(
        description: "llama_chat_apply_template failed to calculate buffer size"
      )
    }

    // Second call: write formatted prompt into buffer
    var buffer = [CChar](repeating: 0, count: Int(requiredSize) + 1)
    let written = llama_chat_apply_template(
      nil, &messages, messages.count, true, &buffer, Int32(buffer.count)
    )
    guard written > 0 else {
      throw LLMError.generationFailed(
        description: "llama_chat_apply_template failed"
      )
    }

    return String(cString: buffer)
  }
}
