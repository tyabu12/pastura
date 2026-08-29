package com.pastura.models

import platform.Foundation.NSBundle

/**
 * Resolves the key against `Bundle.main`'s `Localizable` table.
 *
 * The Swift side's `String(localized:)` resolves against exactly that table, so
 * inside the iOS app this reads the same compiled `Localizable.xcstrings` the
 * Swift twins do — which is the whole point of this leaf. On the catalog-less
 * Apple hosts (the macOS parity harness, the gate spike) no entry is found and
 * the supplied default — the key itself — comes back unchanged, which is what
 * keeps the English `commonTest` pins green on the `macosArm64Test` rung.
 */
internal actual fun localizedFormat(key: String): String =
    NSBundle.mainBundle.localizedStringForKey(key, key, null)
