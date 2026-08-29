package com.pastura.models

/**
 * Resolves an English catalog key to the platform's localized format string.
 *
 * The key **is** the English format string as it appears in
 * `Pastura/Pastura/Resources/Localizable.xcstrings` (the Swift side's
 * `String(localized:)` argument), so a platform with no catalog can honour the
 * contract by returning the key itself — which is exactly what the JVM and the
 * catalog-less Apple hosts (macOS harness, gate spike) do.
 *
 * @param key the English format string used as the catalog key.
 * @return the localized format string, or [key] when no catalog entry exists.
 */
internal expect fun localizedFormat(key: String): String

/**
 * A localizable message: an English catalog key plus its positional arguments.
 *
 * Splitting the key from the arguments is what makes localization possible —
 * the key is resolved through [localizedFormat] at render time, so a translated
 * value (which may reorder its arguments via `%N$@` forms) can be substituted
 * into instead of the English one.
 *
 * @property format the English format string, doubling as the catalog key.
 * @property args the arguments, in the order the English format consumes them.
 */
internal data class Rendering(val format: String, val args: List<Any>) {
    /** Resolves [format] through the platform catalog and substitutes [args]. */
    fun render(): String = substitute(localizedFormat(format), args)
}

/**
 * Substitutes [args] into a `String(format:)`-style [format] string.
 *
 * Recognises exactly the four specifier forms the Pastura catalog uses: `%@`
 * and `%lld` (consuming arguments sequentially) and their positional
 * counterparts `%N$@` and `%N$lld` (1-based index into [args]). The two kinds
 * keep **independent** counters: a bare specifier advances only the sequential
 * one and never the positional index. Mixing them is unspecified in Foundation's
 * `String(format:)` too, so this is a documented house rule rather than a
 * behaviour to match.
 *
 * Arguments are rendered with `toString()`, which constrains what [args] may
 * hold: `String` for `%@`, `Int` / `Long` for `%lld`, nothing else — a `Double`
 * would render Kotlin's `1.0E-4` where Swift formats differently, and no
 * message case carries one. `%%` is **not** collapsed to `%` (Foundation
 * does); the catalog coverage test rejects any `%` outside the four forms
 * above, so the divergence cannot enter through a translation unnoticed.
 *
 * @param format the (possibly localized) format string.
 * @param args the arguments to substitute.
 * @return the substituted string.
 */
internal fun substitute(format: String, args: List<Any>): String {
    val out = StringBuilder(format.length + 16)
    var i = 0
    var nextSequentialArg = 0
    while (i < format.length) {
        val c = format[i]
        if (c != '%') {
            out.append(c)
            i++
            continue
        }
        // Try `%N$` first: read the digits, then require the `$`.
        var j = i + 1
        var digitsEnd = j
        while (digitsEnd < format.length && format[digitsEnd] in '0'..'9') digitsEnd++
        var argIndex: Int? = null
        var isPositional = false
        if (digitsEnd > j && digitsEnd < format.length && format[digitsEnd] == '$') {
            val parsed = format.substring(j, digitsEnd).toIntOrNull()
            if (parsed != null && parsed >= 1) {
                argIndex = parsed - 1
                isPositional = true
                j = digitsEnd + 1
            }
        }
        val conversion = when {
            format.startsWith("@", j) -> "@"
            format.startsWith("lld", j) -> "lld"
            else -> null
        }
        if (conversion == null) {
            // Any `%` sequence outside the recognised set — `%d`, `%%`, a bare
            // trailing `%`, a `%0$@` — is copied through literally. This runs on
            // the validator's throw path, where a malformed or unexpected
            // localization value must degrade to slightly-wrong text rather than
            // throw a second exception on top of the one being reported.
            out.append(c)
            i++
            continue
        }
        if (!isPositional) {
            argIndex = nextSequentialArg
        }
        val value = argIndex?.let { args.getOrNull(it) }
        if (value == null) {
            // Out-of-range index, or more specifiers than arguments: leave the
            // whole specifier in the output rather than dropping it, so the
            // mismatch is visible in the message instead of silently vanishing.
            out.append(format, i, j + conversion.length)
        } else {
            // Appended verbatim and NOT re-scanned: arguments carry user-supplied
            // scenario text, so an argument containing `%@` must survive as
            // literal text and must never consume the next argument.
            out.append(value.toString())
            if (!isPositional) nextSequentialArg++
        }
        i = j + conversion.length
    }
    return out.toString()
}
