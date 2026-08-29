package com.pastura.models

/**
 * The JVM rung has no string catalog, so the English key is the format string.
 *
 * Identity is also what keeps the English pins in `commonTest` the detector for
 * a message reword — a JVM lookup that could resolve to something else would
 * make those pins depend on a resource bundle instead of on the literals.
 */
internal actual fun localizedFormat(key: String): String = key
