package com.pastura.models

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Asserts that every `Rendering.format` produced by the two Models-layer message
 * types is a LIVE, translated key of `Pastura/Pastura/Resources/Localizable.xcstrings`.
 *
 * ## Why this test exists
 *
 * On Apple targets `localizedFormat(key)` resolves through `NSBundle.mainBundle`,
 * and Foundation's lookup **falls back to the key itself** when the key is absent,
 * stale, or untranslated. So a Kotlin format string that has drifted from the
 * Swift `String(localized:)` literal — a reword on the Swift side, a
 * `xcstringstool sync` that retired the old key — produces a perfectly readable
 * English string in the iOS app and silently loses its Japanese translation.
 * Nothing else in the repo detects that: `check-prompt-literal-parity.py` scopes
 * itself to `Engine/` + `LLM/` and never reaches `Models/`
 * (`.claude/rules/kmp-interop.md` § Pattern 4), and the commonTest roster pins
 * compare Kotlin against a hand-transcribed expectation, not against the catalog.
 *
 * ## What is checked, per case
 *
 * a. the format exists as a catalog key;
 * b. it is not `extractionState == "stale"` (`xcstringstool sync` keeps retired
 *    keys around with that marker, so mere presence proves nothing);
 * c. it has a `ja` localization in state `translated`;
 * d. the `ja` value's specifier multiset equals the key's. A translation that
 *    drops or duplicates a `%@` / `%lld` renders wrong (or renders a stale
 *    argument) at runtime, and (c) alone would pass it. Positional forms
 *    (`%N$@` / `%N$lld`) are normalised to their bare counterparts first, since
 *    a Japanese translation legitimately reorders arguments.
 *
 * Failures are collected and reported together: a Swift-side reword typically
 * breaks a whole family of keys at once, and a first-failure abort would hide
 * all but one.
 *
 * ## Roster source
 *
 * The case lists are the commonTest rosters (`rosterWithExpectedRenderings()`),
 * reused rather than duplicated — jvmTest and commonTest are one test
 * compilation. [rosterIsComplete] pins the totals so a roster that shrinks makes
 * this file loud rather than quietly narrowing its own coverage.
 */
class MessageCatalogCoverageTests {

    private companion object {
        /** Case counts pinned by the two commonTest roster suites (53 + 22). */
        const val VALIDATION_CASE_COUNT = 53
        const val LINT_CASE_COUNT = 22

        /**
         * Injected by `shared/models/build.gradle.kts` as an absolute path, so
         * the read does not depend on Gradle's test working directory.
         */
        const val CATALOG_PATH_PROPERTY = "pastura.xcstringsPath"
    }

    /** One roster entry: a human-readable case label plus the catalog key it renders through. */
    private data class Entry(val label: String, val format: String)

    private fun entries(): List<Entry> =
        ScenarioValidationMessageTests().rosterWithExpectedRenderings().map { (message, _) ->
            Entry("ScenarioValidationMessage.${message::class.simpleName}", message.rendering().format)
        } + ScenarioLintMessageTests().rosterWithExpectedRenderings().map { (message, _) ->
            Entry("ScenarioLintMessage.${message::class.simpleName}", message.rendering().format)
        }

    private fun catalogStrings(): JsonObject {
        val path = System.getProperty(CATALOG_PATH_PROPERTY)
        // Fail loudly rather than skipping: a silently-unconfigured property
        // would turn this whole suite into a no-op that still reports green.
        assertTrue(
            !path.isNullOrBlank(),
            "System property `$CATALOG_PATH_PROPERTY` is not set — " +
                "see the `tasks.named<Test>(\"jvmTest\")` block in shared/models/build.gradle.kts.",
        )
        val file = File(path)
        assertTrue(file.isFile, "String catalog not found at `$path` (from `$CATALOG_PATH_PROPERTY`).")
        val root = Json.parseToJsonElement(file.readText()).jsonObject
        val strings = root["strings"]
        assertTrue(strings is JsonObject, "String catalog at `$path` has no `strings` object.")
        return strings
    }

    /**
     * Normalises a format string to its specifier multiset, sorted so the
     * comparison is order-insensitive: `%N$@` / `%N$lld` collapse to `%@` /
     * `%lld` because a translation may reorder arguments legitimately, while
     * dropping or duplicating one is the defect this catches.
     */
    private fun specifiers(format: String): List<String> =
        SPECIFIER_PATTERN.findAll(format)
            .map { match -> if (match.value.endsWith("@")) "%@" else "%lld" }
            .sorted()
            .toList()

    @Test
    fun rosterIsComplete() {
        val all = entries()
        assertEquals(
            VALIDATION_CASE_COUNT + LINT_CASE_COUNT,
            all.size,
            "Roster size changed — this suite's coverage is only as wide as the commonTest rosters " +
                "it reuses. Update the pinned counts together with the roster.",
        )
    }

    @Test
    fun everyMessageFormatIsALiveTranslatedCatalogKey() {
        val strings = catalogStrings()
        val failures = mutableListOf<String>()

        for ((label, format) in entries()) {
            val entry = strings[format]?.jsonObject
            if (entry == null) {
                failures += "$label: format is not a catalog key — $format"
                continue
            }
            val extractionState = entry["extractionState"]?.jsonPrimitive?.content
            if (extractionState == "stale") {
                failures += "$label: catalog key is `extractionState: stale` (retired by " +
                    "`xcstringstool sync`; the app falls back to English) — $format"
                continue
            }
            val japanese = entry["localizations"]?.jsonObject?.get("ja")?.jsonObject
                ?.get("stringUnit")?.jsonObject
            val state = japanese?.get("state")?.jsonPrimitive?.content
            if (state != "translated") {
                failures += "$label: `ja` localization is ${state ?: "absent"}, expected `translated` — $format"
                continue
            }
            val value = japanese["value"]?.jsonPrimitive?.content.orEmpty()
            val expected = specifiers(format)
            val actual = specifiers(value)
            if (actual != expected) {
                failures += "$label: `ja` specifiers $actual do not match the key's $expected — " +
                    "key=$format ja=$value"
            }
        }

        assertTrue(
            failures.isEmpty(),
            "${failures.size} message format(s) do not resolve through Localizable.xcstrings.\n" +
                "The Swift `String(localized:)` literal is the source of truth: reword it, run the " +
                "catalog sync, then update the Kotlin twin and its commonTest expected string.\n" +
                failures.joinToString("\n") { "  - $it" },
        )
    }
}

/** `%@`, `%lld` and their positional `%N$…` forms — the four the catalog uses. */
private val SPECIFIER_PATTERN = Regex("""%(?:\d+\$)?(?:@|lld)""")
