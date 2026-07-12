package com.pastura.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Distribution mode for `assign` phases — controls how a source value is mapped
 * to active agents.
 *
 * - [ALL] (default when omitted in YAML): every active agent receives the same
 *   round-indexed item from the source. Source must be a flat list of strings or
 *   a single string.
 * - [RANDOM_ONE]: one randomly-chosen agent receives the `minority` value, the
 *   rest receive `majority`. Source must be a list of `{majority, minority}`
 *   dictionaries (e.g., word wolf topic sets).
 *
 * Kotlin port of `Pastura/Pastura/Models/AssignTarget.swift`.
 */
@Serializable
public enum class AssignTarget {
    /** Every active agent receives the same round-indexed item from the source. */
    @SerialName("all")
    ALL,

    /** One randomly-chosen agent receives the minority value; the rest receive majority. */
    @SerialName("random_one")
    RANDOM_ONE,
}
