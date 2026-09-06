package com.pastura.models

import platform.Foundation.NSBundle

/**
 * Resolves the key against `Bundle.main`'s `Localizable` table.
 *
 * The Swift side's `String(localized:)` resolves against exactly that table, so
 * inside the iOS app this reads the same compiled `Localizable.xcstrings` the
 * Swift twins do — which is the whole point of this leaf. On the catalog-less
 * Apple hosts (the macOS parity harness) no entry is found and
 * the supplied default — the key itself — comes back unchanged, which is what
 * keeps the English `commonTest` pins green on the `macosArm64Test` rung.
 *
 * ⚠️ **Unverified in-app until Stage 5.** No rung exercises the catalog path:
 * `macosArm64Test` hits the fallback above, and the iOS app has no rung that
 * renders a `ja` key through this leaf. The claim that this resolves the same
 * table as `String(localized:)` is therefore a Foundation-documented
 * expectation, not a measurement — the first Stage-5 build must render one
 * key under `ja` from the app before the Stage-5 board row treats it as done.
 */
internal actual fun localizedFormat(key: String): String =
    NSBundle.mainBundle.localizedStringForKey(key, key, null)
