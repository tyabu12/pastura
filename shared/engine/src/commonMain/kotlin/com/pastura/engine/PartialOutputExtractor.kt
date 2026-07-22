package com.pastura.engine

/**
 * Best-effort snapshot of a single LLM inference's currently-emitted fields,
 * derived from a buffer of streamed text.
 *
 * Produced by [PartialOutputExtractor.extract] during incremental generation
 * and consumed by the streaming caller path to push UI updates. The final
 * canonical parse (via [JSONResponseParser]) is still the source of truth on
 * stream end; the extractor's job is to stay *consistent* with that canonical
 * result — every partial primary must be a prefix of the final one.
 *
 * A `data class` gives the Swift original's `Equatable` for free.
 *
 * Swift original: `Pastura/Pastura/LLM/PartialOutputExtractor.swift`.
 */
internal data class PartialSnapshot(
    /**
     * Currently-visible value of the first primary key present in the buffer
     * (one of [PartialOutputExtractor.primaryKeys] —
     * `statement` / `action` / `vote` / `note`). `null` while the extractor is
     * waiting for that key's opening quote.
     */
    val primary: String?,
    /**
     * Currently-visible value of `inner_thought`, or `null` until its opening
     * quote has arrived.
     */
    val thought: String?,
) {
    companion object {
        val empty = PartialSnapshot(null, null)
    }
}

/**
 * Extracts best-effort `(primary, thought)` snapshots from partial LLM output
 * text. Stateless — each [extract] call parses the entire buffer fresh.
 *
 * Strategy:
 * 1. Strip closed Gemma / generic thinking tags.
 * 2. If an *unclosed* thinking tag is present, yield an empty snapshot (the
 *    model is still reasoning; nothing is safe to display).
 * 3. Otherwise locate the first `{` and scan for top-level `"<key>":"..."` pairs
 *    that correspond to known primary keys or [thoughtKey].
 * 4. Decode escape sequences inside string values; hold back incomplete escapes
 *    (`\`, partial `\uXXXX`) so the UI never sees invalid characters mid-type.
 *
 * Top-level detection uses a cheap heuristic — a candidate `"<key>"` is treated
 * as a real key only when it is both followed by `:` and preceded by `{` or `,`
 * (ignoring whitespace). This rejects key-like substrings that appear inside
 * string values.
 *
 * Swift original: `Pastura/Pastura/LLM/PartialOutputExtractor.swift`.
 */
internal class PartialOutputExtractor {

    companion object {
        /**
         * Recognised primary-output keys in the order they are checked (one
         * canonical field per LLM phase: speak → `statement`, choose → `action`,
         * vote → `vote`, reflect → `note`).
         */
        val primaryKeys = listOf("statement", "action", "vote", "note")
        const val thoughtKey = "inner_thought"

        // Duplicated intentionally from JSONResponseParser.kt's CHANNEL_THINKING /
        // THINK_TAG — mirrors the Swift original's own two-copy structure; do NOT
        // DRY-merge. `[\s\S]` encodes "any char incl. newline" without
        // RegexOption.DOT_MATCHES_ALL, which is JVM/Native-only and absent from
        // commonMain (see JSONResponseParser.kt L43-52).
        private val channelThinkingRegex = Regex("""<\|channel>thought\s*[\s\S]*?<channel\|>""")
        private val thinkTagRegex = Regex("""<think>[\s\S]*?</think>""")
    }

    /**
     * Extract a best-effort `(primary, thought)` snapshot from a partial buffer.
     *
     * [thoughtKey] is the secondary field to surface as the snapshot's `thought`.
     * Defaults to [PartialOutputExtractor.thoughtKey] (`inner_thought`). The
     * caller passes the schema-derived key (e.g. `reason` for vote) so the live
     * streaming THINKING section sources the phase's actual private-thought field
     * (#609).
     */
    fun extract(
        text: String,
        thoughtKey: String = PartialOutputExtractor.thoughtKey,
    ): PartialSnapshot {
        val stripped = stripClosedThinkingTags(text)
        if (hasUnclosedThinkingTag(stripped)) {
            return PartialSnapshot.empty
        }
        val braceIdx = stripped.indexOf('{')
        if (braceIdx < 0) {
            return PartialSnapshot.empty
        }
        val jsonPart = stripped.substring(braceIdx)

        var primary: String? = null
        for (key in primaryKeys) {
            val value = extractTopLevelStringValue(key, jsonPart)
            if (value != null) {
                primary = value
                break
            }
        }
        val thought = extractTopLevelStringValue(thoughtKey, jsonPart)

        return PartialSnapshot(primary = primary, thought = thought)
    }

    // MARK: - Thinking-tag handling

    private fun stripClosedThinkingTags(text: String): String {
        var result = channelThinkingRegex.replace(text, "")
        result = thinkTagRegex.replace(result, "")
        return result
    }

    /**
     * After stripping closed tags, an opener that still appears means the model
     * is still generating reasoning — emission must wait.
     */
    private fun hasUnclosedThinkingTag(text: String): Boolean =
        text.contains("<|channel>") || text.contains("<think>")

    // MARK: - Top-level key lookup

    /**
     * Find a top-level `"<key>"` position in the JSON-ish buffer. Returns the
     * index immediately after the closing quote of the key, or `null` if no
     * top-level occurrence is found.
     */
    private fun findTopLevelKey(key: String, json: String): Int? {
        val pattern = "\"$key\""
        var searchStart = 0
        while (searchStart <= json.length) {
            val start = json.indexOf(pattern, searchStart)
            if (start < 0) {
                return null
            }
            val end = start + pattern.length

            val followedByColon = isFollowedByColon(end, json)
            val precededByOpener = isPrecededByOpener(start, json)

            if (followedByColon && precededByOpener) {
                return end
            }
            searchStart = end
        }
        return null
    }

    private fun isFollowedByColon(idx: Int, json: String): Boolean {
        var i = idx
        while (i < json.length && json[i].isWhitespace()) {
            i++
        }
        return i < json.length && json[i] == ':'
    }

    private fun isPrecededByOpener(idx: Int, json: String): Boolean {
        var i = idx
        while (i > 0) {
            i--
            val char = json[i]
            if (!char.isWhitespace()) {
                return char == '{' || char == ','
            }
        }
        return false
    }

    // MARK: - String-value extraction

    /**
     * Scan `"<key>"\s*:\s*"<decoded-value>"` at the top level. Returns:
     * - `null` if the key has not been observed yet at top level.
     * - `null` if the key exists but no value colon/opening-quote yet.
     * - `""` once the opening quote is past but no content has arrived.
     * - decoded partial content thereafter, holding back any incomplete trailing
     *   escape.
     */
    private fun extractTopLevelStringValue(targetKey: String, json: String): String? {
        val afterKey = findTopLevelKey(targetKey, json) ?: return null

        var i = afterKey
        while (i < json.length && json[i].isWhitespace()) {
            i++
        }
        if (i >= json.length || json[i] != ':') return null
        i++
        while (i < json.length && json[i].isWhitespace()) {
            i++
        }
        if (i >= json.length || json[i] != '"') return null
        i++

        return decodeStringContent(i, json)
    }

    /**
     * Decode JSON string content up to the first unescaped `"` or the end of
     * buffer. Holds back incomplete trailing escapes so the UI never renders a
     * lone backslash or a partial `\uXXXX`.
     */
    private fun decodeStringContent(start: Int, json: String): String {
        val decoded = StringBuilder()
        var i = start
        while (i < json.length) {
            val char = json[i]
            if (char == '"') {
                return decoded.toString()
            }
            if (char == '\\') {
                val next = i + 1
                if (next >= json.length) return decoded.toString()
                val escChar = json[next]
                when (escChar) {
                    '"' -> decoded.append('"')
                    '\\' -> decoded.append('\\')
                    '/' -> decoded.append('/')
                    'n' -> decoded.append('\n')
                    't' -> decoded.append('\t')
                    'r' -> decoded.append('\r')
                    'b' -> decoded.append('\u0008')
                    'f' -> decoded.append('\u000C')
                    'u' -> {
                        val hexStart = next + 1
                        val hexEnd = hexStart + 4
                        if (hexEnd > json.length) return decoded.toString()
                        val hex = json.substring(hexStart, hexEnd)
                        // GUARD 1 (hex-charset): reject a leading sign / garbage
                        // that Swift's unsigned UInt32(_:radix:) rejects but
                        // Kotlin's toIntOrNull(16) would ACCEPT (e.g. `\u-0ff` →
                        // -255) — a real cross-language parity gap.
                        if (!hex.all { it.digitToIntOrNull(16) != null }) {
                            return decoded.toString()
                        }
                        val code = hex.toInt(16)
                        // GUARD 2 (surrogate): mirrors Swift Unicode.Scalar(code)
                        // returning nil for surrogate code points.
                        if (code in 0xD800..0xDFFF) {
                            return decoded.toString()
                        }
                        decoded.append(code.toChar())
                        i = hexEnd
                        continue
                    }
                    else -> {
                        // Unknown escape — preserve both chars verbatim so the
                        // final canonical parse remains authoritative on meaning.
                        decoded.append(char)
                        decoded.append(escChar)
                    }
                }
                i = next + 1
                continue
            }
            decoded.append(char)
            i++
        }
        return decoded.toString()
    }
}
