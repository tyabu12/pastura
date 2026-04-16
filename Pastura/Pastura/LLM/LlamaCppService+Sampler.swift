import Foundation
import LlamaSwift

// MARK: - Sampler

extension LlamaCppService {
  func createSampler() throws -> UnsafeMutablePointer<llama_sampler> {
    let sparams = llama_sampler_chain_default_params()
    guard let chain = llama_sampler_chain_init(sparams) else {
      throw LLMError.generationFailed(description: "Failed to initialize sampler chain")
    }

    // Order: penalties → top_k → top_p → temperature → dist
    // Penalties on full vocab first, then narrow, then temperature, then selection
    llama_sampler_chain_add(
      chain,
      llama_sampler_init_penalties(
        64,  // penalty_last_n: look back 64 tokens
        Self.repeatPenalty,  // repeat_penalty: 1.1
        0.0,  // freq_penalty: disabled
        0.0  // presence_penalty: disabled
      ))
    llama_sampler_chain_add(chain, llama_sampler_init_top_k(Self.topK))
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(Self.topP, 1))
    llama_sampler_chain_add(chain, llama_sampler_init_temp(Self.temperature))
    llama_sampler_chain_add(
      chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

    return chain
  }
}
