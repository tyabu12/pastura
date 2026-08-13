package com.pastura.models

/**
 * The turn-boundary sentinels a model's chat template writes around one turn,
 * **as plaintext**.
 *
 * Kotlin port of `Pastura/Pastura/Models/ChatTurnMarkers.swift` (#1422).
 *
 * ### Contract for consumers
 *
 * Match these against **decoded text only**. They are not the tokenizer's
 * turn-boundary *tokens*: under llama.cpp a genuine CONTROL token decodes to
 * the empty string and an end-of-generation token returns before its piece is
 * appended, so a marker can only ever reach a text match when the model
 * **hallucinates it as ordinary characters**.
 *
 * ### Why per-model
 *
 * The values are tokenizer-specific and share no convention across families.
 * ChatML models (Qwen 3) use `<|im_start|>` / `<|im_end|>`; Gemma 4 uses
 * `<|turn>` / `<turn|>` and carries neither ChatML string anywhere in its
 * 262,144-token vocabulary. Hardcoding the ChatML pair — as both engines did
 * until #1422 — leaves every mechanism keyed on it silently inert for the
 * default shipped model.
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
