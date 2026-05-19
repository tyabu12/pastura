import Foundation
import LlamaSwift

/// Swift facade over the SafeSampler Obj-C++ bridge.
///
/// Two roles:
///   1. Hide the raw `pastura_sample_result_t` C struct from production
///      callers — they receive a Swift-native ``Outcome`` instead of dealing
///      with the `(CChar, CChar, ..., CChar)` tuple Swift's importer produces
///      for the fixed-size `error_message[512]` field.
///   2. Provide an `internal`-visible surface so `SafeSamplerTests` can
///      exercise the DEBUG-only throw simulators through
///      `@testable import Pastura`, without setting up a separate bridging
///      header on the test target.
///
/// The catch scope is documented in `LLM/SafeSampler.h`. The wrapper does
/// not cover SIGABRT-class crashes (issue #253); it covers C++ exceptions
/// from the sample / chain-accept path (issue #334 single-field grammar,
/// issue #366 Qwen 3 `<think>` token, issue #371 special-token mask gap).
nonisolated enum SafeSampler {
  /// Calls `llama_sampler_sample` through the C++ exception-catching
  /// bridge. The sampler pointer matches what `createSampler` returns; the
  /// context is `OpaquePointer` because `llama_context` is forward-declared
  /// opaquely in `llama.h`. The Swift importer merges the forward
  /// declarations in `SafeSampler.h` with LlamaSwift's full definitions, so
  /// `pastura_llama_sampler_sample_safe` is imported with these typed
  /// arguments — we re-state them here to keep the facade's call ergonomics
  /// aligned with the existing `llama_sampler_sample` callsites.
  static func sample(
    sampler: UnsafeMutablePointer<llama_sampler>, context: OpaquePointer,
    idx: Int32
  ) -> Outcome {
    Outcome(raw: pastura_llama_sampler_sample_safe(sampler, context, idx))
  }

  /// Result of a wrapped sample call.
  nonisolated struct Outcome: Equatable, Sendable {
    /// Sampled token id. Meaningful only when ``errorMessage`` is `nil`.
    let token: Int32

    /// `nil` when the underlying sample call returned normally; otherwise
    /// the (possibly truncated) `what()` of the caught C++ exception.
    /// Truncation contract: payloads longer than
    /// `PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE - 1` are cut to that length
    /// and NUL-terminated; see `LLM/SafeSampler.h`.
    let errorMessage: String?

    init(raw: pastura_sample_result_t) {
      self.token = raw.token
      self.errorMessage = raw.did_throw ? raw.errorMessageString : nil
    }
  }
}

/// Lift the imported fixed-size `error_message[N]` tuple into a Swift
/// `String`. Internal because only `SafeSampler.Outcome.init` and the
/// `SafeSamplerTests` truncation test consume it.
nonisolated extension pastura_sample_result_t {
  var errorMessageString: String {
    withUnsafePointer(to: self.error_message) { tuplePtr in
      let charPtr = UnsafeRawPointer(tuplePtr).assumingMemoryBound(to: CChar.self)
      return String(cString: charPtr)
    }
  }
}

#if DEBUG
  /// Test hooks: forward to the DEBUG-only C entry points that intentionally
  /// throw + catch. Exposed at `internal` access so tests can call through
  /// `@testable import Pastura`. Not callable from Release builds (the
  /// underlying C symbols are `#ifdef DEBUG`-gated in `SafeSampler.h`).
  nonisolated enum SafeSamplerTestHooks {
    static func throwPath() -> SafeSampler.Outcome {
      SafeSampler.Outcome(raw: pastura_test_safe_sampler_throw_path())
    }

    static func throwLongPayload() -> SafeSampler.Outcome {
      SafeSampler.Outcome(raw: pastura_test_safe_sampler_throw_long_payload())
    }
  }
#endif
