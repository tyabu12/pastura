package com.pastura.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Swift-callable facade for kotlinx.serialization encoding of [Scenario] —
 * Issue #220 W4 PR-A.
 *
 * **Why this exists:** kotlinx.serialization's top-level encode operations
 * (`Json.encodeToString<T>(value)`, `Json.encodeToJsonElement<T>(value)`)
 * rely on `reified` type parameters resolved at compile time. Kotlin/Native's
 * Swift export collapses `reified` generics — the Swift caller cannot
 * invoke them directly. The explicit-serializer overloads
 * (`Json.encodeToString(serializer, value)`) ARE exported but require
 * passing the serializer instance, which is ergonomically heavy from Swift.
 *
 * This object exposes concrete-type signatures the Swift consumer can call
 * without touching either reified generics or KSerializer types.
 *
 * **encode-only by design** (W4 PR-A scope decision per W3 PR-C plan v4
 * Option γ-prime): the W4 H4 measurement only exercises the encode path;
 * Swift→K/N decode is NOT on the production iOS graph (YAML → `Scenario`
 * decoding stays Swift-side via `ScenarioLoader`). Adding a decode surface
 * here would be premature — W4 PR-C snakeyaml validation work may need it,
 * in which case it lands then.
 *
 * **Json instance choice:** `Json` (companion object — kotlinx-serialization
 * default settings) matches existing `commonTest/` usage. No custom
 * configuration (`isLenient`, `ignoreUnknownKeys`) — production scenarios
 * use strict schemas and the spike's measurement should reflect that.
 *
 * **No `@Throws`, deliberately (#1553).** Both functions are exported to Swift,
 * where an un-annotated Kotlin throw terminates the caller rather than raising
 * (`.claude/rules/kmp-interop.md` Pattern 5). `Json.encodeToString` can throw
 * `SerializationException` in principle, but today's `Scenario` shape does not
 * reach that path, so neither is pinned by the header gate. Revisit if the
 * schema gains a polymorphic field or a non-finite `Double`.
 */
public object ScenarioCodec {

    /**
     * Encode [scenario] to the canonical [JsonElement] tree.
     *
     * Returned tree is suitable as input to [Canonicalizer.canonicalize] for
     * cross-language wire-shape comparison (PR-B harness pattern).
     */
    public fun encodeToJsonElement(scenario: Scenario): JsonElement =
        Json.encodeToJsonElement(Scenario.serializer(), scenario)

    /**
     * Encode [scenario] to a JSON string (default kotlinx-serialization
     * compact form — no pretty-printing).
     */
    public fun encodeToString(scenario: Scenario): String =
        Json.encodeToString(Scenario.serializer(), scenario)
}
