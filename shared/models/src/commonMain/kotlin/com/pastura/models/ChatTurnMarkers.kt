package com.pastura.models

/**
 * The turn-boundary sentinels a model's chat template writes around one turn,
 * **as plaintext**.
 *
 * Kotlin port of `Pastura/Pastura/Models/ChatTurnMarkers.swift` (#1422).
 *
 * ### Contract for consumers
 *
 * Match these against **decoded text only**, never the tokenizer's turn-boundary tokens — a
 * genuine CONTROL token never decodes to visible text. See the Swift original for the full
 * argument.
 *
 * ### Why per-model
 *
 * Values are tokenizer-specific with no shared convention: ChatML (Qwen 3) uses
 * `<|im_start|>`/`<|im_end|>`, Gemma 4 uses `<|turn>`/`<turn|>`. Hardcoding the ChatML pair, as
 * both engines did until #1422, left every consumer silently inert for the default shipped model.
 *
 * **Deliberately not `@Serializable`.** It is a runtime parameter of the parse
 * path, never a persisted or K/N-serialized payload, so it does not cross
 * ADR-023 §5.2 and needs no golden entry (§12 condition 2). Behaviour parity
 * with Swift is covered by the ported truncation tests instead.
 *
 * @property start Plaintext sentinel that opens a turn (e.g. `"<|im_start|>"`).
 * @property end   Plaintext sentinel that closes a turn (e.g. `"<|im_end|>"`).
 */
public data class ChatTurnMarkers(
    val start: String,
    val end: String,
) {
    public companion object {
        /**
         * The ChatML pair — Qwen 3 and the wider ChatML family, and the
         * baseline every consumer keeps in its effective set regardless of
         * which model is loaded.
         */
        public val chatML: ChatTurnMarkers = ChatTurnMarkers(start = "<|im_start|>", end = "<|im_end|>")
    }
}
