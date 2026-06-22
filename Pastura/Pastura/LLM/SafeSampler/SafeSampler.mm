//
//  SafeSampler.mm
//
//  Implementation of the SafeSampler bridge. See SafeSampler.h for the
//  contract and the rationale.
//
//  This file is LLM-layer only — do NOT import Engine, Data, or App
//  headers. The sequential-access contract (ADR-002 §6) lives in
//  LlamaCppService; the wrapper here is stateless and re-entrant.
//

// Critic Axis 3: assert exceptions are enabled at compile time rather than
// silently degrading to `std::terminate` if a future pbxproj edit flips
// GCC_ENABLE_CPP_EXCEPTIONS to NO.
#if !__cpp_exceptions
#error "SafeSampler.mm requires C++ exceptions. Set GCC_ENABLE_CPP_EXCEPTIONS=YES."
#endif

#import "SafeSampler.h"

#include <cstring>
#include <exception>
#include <stdexcept>
#include <string>

// We deliberately declare the C-ABI prototype of `llama_sampler_sample` here
// instead of including `<llama/llama.h>`. Three reasons:
//   1. The umbrella header is C++-tinted and brings in dozens of unrelated
//      symbols; we only need this one function.
//   2. Header-include paths for SPM binary frameworks (llama.swift exposes
//      llama.cpp as a binary target) shift between SPM versions; relying on
//      a manual extern decl keeps the wrapper insulated.
//   3. The signature has been stable across llama.cpp b8694+: `llama_token`
//      is a `typedef int32_t`. A future signature change would surface as a
//      link error, not silent UB.
extern "C" int32_t llama_sampler_sample(
    struct llama_sampler *smpl, struct llama_context *ctx, int32_t idx);

// `llama_sampler_accept(smpl, token)` advances every chain component
// (penalties ring buffer, grammar state). Same manual-extern rationale as
// `llama_sampler_sample` above: `llama_token` is a `typedef int32_t` and the
// signature is stable across llama.cpp b8694+. Declared here so the
// EOG-guarded split sampling in `LlamaCppService` can wrap just the accept
// step in the C++ exception catcher (the grammar `accept_token` throw, #334).
extern "C" void llama_sampler_accept(struct llama_sampler *smpl, int32_t token);

namespace {

void fill_error_message(
    char (&buffer)[PASTURA_SAFE_SAMPLER_ERROR_BUFFER_SIZE],
    const char *message) {
  // Bounded copy with explicit NUL on the last byte. `strncpy` is allowed
  // not to NUL-terminate when `message` is longer than the buffer; the
  // manual write covers that case.
  std::strncpy(buffer, message, sizeof(buffer) - 1);
  buffer[sizeof(buffer) - 1] = '\0';
}

void reset_result(pastura_sample_result_t &result) {
  result.token = 0;
  result.did_throw = false;
  result.error_message[0] = '\0';
}

}  // namespace

extern "C" {

pastura_sample_result_t pastura_llama_sampler_sample_safe(
    struct llama_sampler *sampler, struct llama_context *ctx, int32_t idx) {
  pastura_sample_result_t result;
  reset_result(result);

  try {
    result.token = llama_sampler_sample(sampler, ctx, idx);
  } catch (const std::exception &e) {
    result.did_throw = true;
    fill_error_message(result.error_message, e.what());
  } catch (...) {
    result.did_throw = true;
    fill_error_message(
        result.error_message,
        "Unknown non-std exception caught in SafeSampler wrapper");
  }
  return result;
}

pastura_sample_result_t pastura_llama_sampler_accept_safe(
    struct llama_sampler *sampler, int32_t token) {
  pastura_sample_result_t result;
  reset_result(result);
  // Echo the accepted token so the Swift facade's `Outcome.token` stays
  // meaningful on the success path (the caller already holds it, but this
  // keeps the success/throw shape uniform with the sample wrapper).
  result.token = token;

  try {
    llama_sampler_accept(sampler, token);
  } catch (const std::exception &e) {
    result.did_throw = true;
    fill_error_message(result.error_message, e.what());
  } catch (...) {
    result.did_throw = true;
    fill_error_message(
        result.error_message,
        "Unknown non-std exception caught in SafeSampler accept wrapper");
  }
  return result;
}

#ifdef DEBUG
pastura_sample_result_t pastura_test_safe_sampler_throw_path(void) {
  pastura_sample_result_t result;
  reset_result(result);

  try {
    // Payload mirrors the exception message reported by issue #334 so the
    // test assertions stay narrative-aligned with the real-world crash.
    throw std::runtime_error(
        "Unexpected empty grammar stack after accepting piece: Hello (9259)");
  } catch (const std::exception &e) {
    result.did_throw = true;
    fill_error_message(result.error_message, e.what());
  }
  return result;
}

pastura_sample_result_t pastura_test_safe_sampler_throw_long_payload(void) {
  pastura_sample_result_t result;
  reset_result(result);

  try {
    // 600 'X' chars + a recognizable trailing marker — exceeds the
    // 512-byte buffer so the truncation + NUL-termination contract is
    // exercised. The trailing "TAIL_MARKER" guarantees a test that checks
    // for "TAIL_MARKER" in the truncated message correctly observes its
    // absence (i.e., truncation actually happened).
    std::string payload(600, 'X');
    payload += "TAIL_MARKER";
    throw std::runtime_error(payload);
  } catch (const std::exception &e) {
    result.did_throw = true;
    fill_error_message(result.error_message, e.what());
  }
  return result;
}
#endif

}  // extern "C"
