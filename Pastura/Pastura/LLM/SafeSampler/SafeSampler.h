//
//  SafeSampler.h
//
//  C-compatible bridge for `llama_sampler_sample` that catches the C++
//  exceptions thrown from llama.cpp's grammar accept path. Without this
//  bridge, an uncaught `std::runtime_error` (from
//  `llama_grammar_accept_token`, e.g. issue #334 single-field grammar repro,
//  issue #366 Qwen 3 `<think>` token) crosses the Swift boundary and
//  `std::terminate` kills the process. Swift cannot catch C++ exceptions
//  directly, so the catch must happen in an Obj-C++ translation unit.
//
//  Scope (covered):
//    * `std::runtime_error: Unexpected empty grammar stack after accepting
//      piece: …` (non-EOG path at `llama-grammar.cpp:~1507` of b8694).
//    * Any other `std::exception` raised from the sample / chain-accept
//      stack — including future llama.cpp bumps that introduce new throws.
//
//  Scope (NOT covered):
//    * `GGML_ABORT` (SIGABRT) cannot be caught here — POSIX signals do not
//      propagate through `try/catch`. The #253 EOG-path abort at
//      `llama-grammar.cpp:1435` is instead AVOIDED upstream of this bridge:
//      `LlamaCppService` splits sampling into apply + accept and skips
//      `llama_sampler_accept` for EOG tokens (which would advance the
//      grammar into the never-used post-EOG state that triggers the abort).
//      See `pastura_llama_sampler_accept_safe` below and
//      `LlamaCppService+Sampler.swift`. A SIGABRT from any other source
//      still terminates the process.
//    * Decode failures returned via `llama_decode`'s non-zero result code
//      (handled by `LlamaCppService.decodeFailureError`).
//

#ifndef PASTURA_SAFE_SAMPLER_H
#define PASTURA_SAFE_SAMPLER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Forward declarations of opaque llama.cpp types. Pulling in
/// `<llama/llama.h>` here would force every Swift consumer to transitively
/// see C++ headers; keeping these opaque confines C++ visibility to the
/// `.mm` translation unit.
struct llama_sampler;
struct llama_context;

/// Maximum captured length of `std::exception::what()`. Real-world payloads
/// from llama.cpp's grammar parser are 80-200 chars (e.g. "Unexpected empty
/// grammar stack after accepting piece: Hello (9259)" is 63 chars); 512
/// gives a comfortable margin. Anything longer is truncated and
/// NUL-terminated; the truncation contract is asserted in SafeSamplerTests.
enum { PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE = 512 };

/// Outcome of `pastura_llama_sampler_sample_safe`.
///
/// - `did_throw == false`: the sample call returned normally; `token` holds
///   the sampled id, `error_message[0] == '\0'`.
/// - `did_throw == true`: a C++ exception was caught; `error_message` holds
///   (up to PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE-1 bytes of)
///   `what()` plus a NUL terminator. `token` is unspecified.
typedef struct {
  int32_t token;
  bool did_throw;
  char error_message[PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE];
} pastura_sample_result_t;

/// Calls `llama_sampler_sample` inside a `try { } catch (...) { }` and
/// returns the outcome.
pastura_sample_result_t pastura_llama_sampler_sample_safe(
    struct llama_sampler *sampler, struct llama_context *ctx, int32_t idx);

/// Calls `llama_sampler_accept` inside a `try { } catch (...) { }` and
/// returns the outcome.
///
/// `LlamaCppService` drives sampling as a split apply + accept (replicating
/// what `llama_sampler_sample` does internally) so it can SKIP this accept
/// for EOG tokens — accepting EOG advances the grammar into the never-used
/// post-EOG state that fires the #253 `GGML_ABORT` at
/// `llama-grammar.cpp:1435`. For every non-EOG token the accept runs exactly
/// as the bundled `llama_sampler_sample` would, so the sampling distribution
/// is unchanged.
///
/// The catch scope is the same `std::exception` set as the sample wrapper:
/// the non-EOG `Unexpected empty grammar stack` throw (#334) originates in
/// the grammar `accept_token` path, so wrapping accept preserves that
/// coverage. The grammar `apply` (logit masking) does not throw
/// `std::exception` (only `GGML_ASSERT` / `GGML_ABORT` signals, which no
/// `try/catch` can intercept), so it does not need a wrapper.
///
/// On the success path `error_message[0] == '\0'` and `token` echoes the
/// accepted token id; on the throw path `did_throw == true` and
/// `error_message` holds the truncated `what()`.
pastura_sample_result_t pastura_llama_sampler_accept_safe(
    struct llama_sampler *sampler, int32_t token);

#ifdef DEBUG
/// DEBUG-only entry point: intentionally throws and catches a
/// `std::runtime_error` whose `what()` matches issue #334's reported payload.
/// Lets SafeSamplerTests validate the catch + marshalling path end-to-end at
/// the Obj-C++ / Swift ABI boundary without needing a real failing grammar.
/// Excluded from Release builds — invoking this in production would
/// guarantee a failure mid-inference.
pastura_sample_result_t pastura_test_safe_sampler_throw_path(void);

/// DEBUG-only entry point: same as above but with a payload longer than
/// PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE, used to verify safe truncation +
/// NUL-termination on overflow.
pastura_sample_result_t pastura_test_safe_sampler_throw_long_payload(void);
#endif

#ifdef __cplusplus
}
#endif

#endif /* PASTURA_SAFE_SAMPLER_H */
