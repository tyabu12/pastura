import Foundation
import Testing

@testable import Pastura

/// End-to-end coverage of the Obj-C++ catch + Swift-marshalling path. We
/// cannot drive a real grammar failure from a unit test (no GGUF model
/// available), so the assertions go through the DEBUG-only throw simulators
/// declared in `SafeSampler.h`. Production Release builds exclude those
/// simulators; this suite therefore only exercises code that ships in the
/// development pipeline (intentional — see `SafeSampler.h` comment on the
/// `#ifdef DEBUG` gating).
///
/// Issue #334 context: production crashes were `std::runtime_error` thrown
/// from `llama_grammar_accept_token`. Without the bridge, those exceptions
/// killed the process; with the bridge, we expect them to materialize as
/// `SafeSampler.Outcome.errorMessage`.
@Suite(.timeLimit(.minutes(1)))
struct SafeSamplerTests {
  #if DEBUG
    @Test("catch path surfaces the C++ exception's what() into Swift")
    func catchPathPropagatesExceptionMessage() {
      let outcome = SafeSamplerTestHooks.throwPath()
      #expect(outcome.errorMessage != nil)
      // The simulator throws a payload mirroring the exact message reported
      // by issue #334 — this asserts the marshalling preserves the text
      // (no UTF-8 corruption, no off-by-one truncation at NUL).
      #expect(
        outcome.errorMessage?.contains(
          "Unexpected empty grammar stack after accepting piece: Hello (9259)") == true,
        "got: \(outcome.errorMessage ?? "<nil>")")
    }

    @Test("error_message buffer truncates safely on payload overflow")
    func truncationContractHoldsForLargePayloads() {
      let outcome = SafeSamplerTestHooks.throwLongPayload()
      let message = outcome.errorMessage ?? ""
      // The simulator constructs a 600-char payload + the recognizable
      // `TAIL_MARKER` suffix. The 512-byte buffer truncates BEFORE the
      // marker, so the marker must NOT appear — proving truncation
      // actually happened and the marshalling did not over-read.
      #expect(
        !message.contains("TAIL_MARKER"),
        "expected truncation to drop TAIL_MARKER suffix; got: \(message)")
      // The Swift-side `String(cString:)` reads up to the first NUL byte.
      // The truncated buffer must therefore yield a string <= buffer-1
      // bytes (the last byte is reserved for `\0`). Since the payload is
      // ASCII, `utf8.count` equals character count but states the contract
      // in byte terms.
      let byteCount = message.utf8.count
      #expect(
        byteCount <= PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE - 1,
        "captured string exceeds buffer-minus-NUL: \(byteCount) bytes")
      // And it should actually be substantial — a too-aggressive truncation
      // (e.g., empty string) would also pass the upper-bound check. The
      // payload-source guarantees at least 400 chars survive truncation.
      #expect(byteCount >= 400, "truncation cut too aggressively: \(byteCount) bytes")
    }

    @Test("accept-wrapper Outcome marshals a successful (no-throw) result")
    func acceptOutcomeSuccessMarshalling() {
      // `pastura_llama_sampler_accept_safe` cannot be exercised end-to-end
      // from the test target: the raw `llama_sampler_*` C symbols are not
      // linked into PasturaTests (only the app dylib links llama; the test
      // bundle sees the `pastura_*` bridge symbols via TEST_HOST but not the
      // underlying llama C-API). Real accept coverage is the macOS harness
      // (ADR-013) per the "Simulator cannot run quantized inference" reality
      // (engine.md / PR #463). Here we lock the Outcome contract for the
      // accept wrapper's success shape: did_throw == false ⇒ errorMessage nil,
      // token echoed. The throw arm shares its `try/catch` + marshalling with
      // the sample wrapper, covered by the simulators above.
      var raw = pastura_sample_result_t()
      raw.token = 7
      raw.did_throw = false
      let outcome = SafeSampler.Outcome(raw: raw)
      #expect(outcome.token == 7)
      #expect(outcome.errorMessage == nil)
    }

    @Test("happy-path callers see no errorMessage")
    func successResultHasNilErrorMessage() {
      // Construct an `Outcome` from a synthetic raw struct that mimics a
      // successful sample (did_throw == false). Avoids exercising the
      // production sampler path which requires a loaded model. This locks
      // in the contract: errorMessage is nil iff did_throw is false.
      var raw = pastura_sample_result_t()
      raw.token = 42
      raw.did_throw = false
      // error_message stays NUL-initialized — the Outcome constructor must
      // ignore it when did_throw is false.
      let outcome = SafeSampler.Outcome(raw: raw)
      #expect(outcome.token == 42)
      #expect(outcome.errorMessage == nil)
    }
  #endif
}
