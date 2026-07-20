import Foundation
import PasturaCore

/// Emits the ADR-023 measurement (v) golden JSON — the Swift-authored wire
/// bytes for `TurnOutput` / `OutputSchema` that the Kotlin parity suite checks
/// against. `TurnOutput` is decoded directly; `OutputSchema` is compared under
/// `Canonicalizer` normalization, since its tag form diverges by design (see
/// `SwiftGoldenParityTests`).
///
/// **Why the harness and not the gate spike.** `tools/kmp-gate-spike` cannot
/// reach these types: SwiftPM forbids a target's `path:` / `sources:` from
/// escaping its package root, and the `Codable` conformances live in
/// `Pastura/Pastura/Models/`. This package already reuses that directory in
/// place (`PasturaCore`), so it is the only Swift build in the repo that can
/// encode the real types rather than a transcription of them.
///
/// **Why goldens rather than a two-sided round trip.** Measurement (v) as
/// written in ADR-023 §6 is a *parity* claim, which needs both encoders in one
/// process — impossible while the Swift types are unreachable from any build
/// that also links Kotlin. Freezing the Swift bytes and decoding them from
/// Kotlin verifies the same seam one-sidedly: it proves Kotlin accepts what
/// Swift produces. It does **not** prove the reverse direction.
package enum GoldenFixtureEmitter {

  /// One frozen sample: a stable identifier plus the exact bytes Swift emits.
  package struct Fixture: Sendable, Equatable {
    /// Identifier used as the Kotlin constant name and the test's label.
    package let name: String
    /// What the sample is meant to exercise, carried into the generated file
    /// so the Kotlin reader is not left guessing why a case exists.
    package let purpose: String
    /// The encoded JSON.
    package let json: String
  }

  /// Canonical encoder settings.
  ///
  /// `sortedKeys` is what makes the output diffable and the `--check` gate
  /// meaningful: `[String: String]` has no inherent order, so an unsorted
  /// encoder would report drift on every regeneration. Mirrors the settings
  /// `shared/models`' baseline generator already uses.
  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    return encoder
  }

  /// Encodes one value into a named fixture.
  private static func encode<T: Encodable>(
    _ value: T,
    _ name: String,
    _ purpose: String
  ) throws -> Fixture {
    let data = try encoder().encode(value)
    guard let json = String(data: data, encoding: .utf8) else {
      throw GoldenFixtureError.notUTF8(name)
    }
    return Fixture(name: name, purpose: purpose, json: json)
  }

  /// Every frozen sample, in emission order.
  package static func fixtures() throws -> [Fixture] {
    try turnOutputFixtures() + outputSchemaFixtures()
  }

  /// The type measurement (v) finds in parity.
  private static func turnOutputFixtures() throws -> [Fixture] {
    [
      try encode(
        TurnOutput(fields: ["statement": "Hello."]),
        "turnOutputSingleField",
        "The speak_all shape — one primary field."
      ),
      try encode(
        TurnOutput(fields: ["statement": "I agree.", "inner_thought": "Not really."]),
        "turnOutputMultipleFields",
        "Primary + secondary field; key order is the encoder's, not the author's."
      ),
      try encode(
        TurnOutput(fields: ["statement": "こんにちは 🐑", "reason": "多バイト値"]),
        "turnOutputMultibyte",
        "CJK + emoji — the value class that crashed the sampler in #597/#599."
      ),
      try encode(
        TurnOutput(fields: [:]),
        "turnOutputEmptyFields",
        "Degenerate but legal: no fields at all."
      ),
      try encode(
        TurnOutput(fields: ["statement": "provenance"], rawText: "{\"statement\": \"provenance\"}"),
        "turnOutputWithRawText",
        """
        `rawText` is set on the Swift value and must NOT appear in the bytes — \
        it is provenance metadata excluded from the wire shape by a custom \
        CodingKeys. Freezing it here makes that exclusion a fact the Kotlin \
        side can rely on rather than a Swift-internal detail.
        """
      )
    ]
  }

  /// The type measurement (v) finds **divergent** — see `SwiftGoldenParityTests`.
  private static func outputSchemaFixtures() throws -> [Fixture] {
    [
      try encode(
        OutputSchema(fields: [OutputSchema.Field(name: "statement", kind: .string)]),
        "outputSchemaStringKind",
        "The speak_all schema — a single `.string` field."
      ),
      try encode(
        OutputSchema(fields: [
          OutputSchema.Field(name: "action", kind: .choice),
          OutputSchema.Field(name: "reason", kind: .string)
        ]),
        "outputSchemaChoiceKind",
        "The choose schema — `.choice` carries no option payload by design."
      )
    ]
  }

  /// Repo-relative path of the generated Kotlin file, so the CLI, the
  /// `--check` gate, and the docs all name it once.
  package static let generatedPath =
    "shared/models/src/commonTest/kotlin/com/pastura/models/SwiftGoldenJson.kt"

  /// The command that regenerates it, quoted in the file header and in the
  /// drift-gate failure message.
  package static let regenerateCommand = "swift run pastura-harness emit-golden --write"

  /// Renders the goldens as a Kotlin source file of raw-string constants.
  ///
  /// **Why generated Kotlin rather than a `.json` resource.** `commonTest`
  /// cannot read resources — `shared/models`' own baseline suites say so and
  /// live in `jvmTest` for exactly that reason. Measurement (v) is worth
  /// having on the Kotlin/Native rung too, and a source constant is the only
  /// form that reaches it. The trade-off bought is a generated file, hence the
  /// `--check` gate.
  package static func kotlinSource() throws -> String {
    var lines: [String] = [
      "// Generated by `\(regenerateCommand)` — DO NOT edit by hand.",
      "//",
      "// The bytes Swift's `Codable` conformances emit for the two types",
      "// ADR-023 §6 measurement (v) names. Frozen here so the Kotlin parity",
      "// suite is checked against the real wire format rather than against a",
      "// transcription of it. See `SwiftGoldenParityTests` for what is asserted",
      "// — `TurnOutput` decoded directly, `OutputSchema` compared under",
      "// `Canonicalizer` normalization because its tag form diverges by design.",
      "//",
      "// Each constant is byte-exact **from the first `{` to the last `}`** — the",
      "// JSON is left at column 0 rather than indented to match the surrounding",
      "// Kotlin, because an indented copy is no longer the thing Swift produced.",
      "//",
      "// Not literally byte-identical, and the difference is worth stating rather",
      "// than rounding off: a Kotlin raw string keeps the newline that follows the",
      "// opening triple-quote and the one preceding the closing one, so every value",
      "// here is `\"\\n\" + <what Swift emitted> + \"\\n\"`. Harmless for the parity",
      "// tests, which decode rather than compare bytes — but a future assertion",
      "// that DOES compare bytes must trim first, and would otherwise fail against",
      "// a claim this header made.",
      "",
      "package com.pastura.models",
      "",
      "internal object SwiftGoldenJson {"
    ]

    for (index, fixture) in try fixtures().enumerated() {
      try assertRawStringSafe(fixture)
      if index > 0 { lines.append("") }
      lines.append("    /**")
      for line in fixture.purpose.split(separator: "\n", omittingEmptySubsequences: false) {
        lines.append(line.isEmpty ? "     *" : "     * \(line)")
      }
      lines.append("     */")
      lines.append("    public const val \(fixture.name): String = \"\"\"")
      lines.append(
        contentsOf: fixture.json
          .split(separator: "\n", omittingEmptySubsequences: false)
          .map(String.init))
      lines.append("\"\"\"")
    }

    lines.append("}")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  /// Rejects bytes that a Kotlin raw string would mangle.
  ///
  /// `"""` would close the literal early and `$` would be read as template
  /// interpolation. Neither occurs in today's fixtures — this exists so a
  /// future addition fails loudly at generation time instead of producing a
  /// Kotlin file that does not compile, or worse, one that compiles with
  /// silently different bytes.
  private static func assertRawStringSafe(_ fixture: Fixture) throws {
    if fixture.json.contains("\"\"\"") {
      throw GoldenFixtureError.rawStringUnsafe(fixture.name, #"a """ sequence"#)
    }
    if fixture.json.contains("$") {
      throw GoldenFixtureError.rawStringUnsafe(fixture.name, "a $ (Kotlin interpolates it)")
    }
  }
}

/// Why a golden could not be produced.
package enum GoldenFixtureError: Error, CustomStringConvertible {
  /// An encoder emitted bytes that are not valid UTF-8.
  case notUTF8(String)
  /// A fixture contains bytes a Kotlin raw string cannot carry verbatim.
  case rawStringUnsafe(String, String)

  package var description: String {
    switch self {
    case .notUTF8(let name):
      return "golden '\(name)' encoded to non-UTF-8 bytes"
    case .rawStringUnsafe(let name, let reason):
      return "golden '\(name)' cannot be embedded in a Kotlin raw string: it contains \(reason)"
    }
  }
}
