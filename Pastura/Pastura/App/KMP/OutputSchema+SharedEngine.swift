import Foundation
import PasturaSharedEngine

// `OutputSchema` (and its `Field` / `Kind` members) is one of the Kotlin types
// with a Swift twin in this module, so every Kotlin spelling below is qualified
// `PasturaSharedEngine.X` — a bare name binds to the Swift twin
// (`.claude/rules/kmp-interop.md` Pattern 1b). No typealias: an alias would hide
// the shadowing from the next reader.
//
// The nested members export as Swift nested types — `PasturaSharedEngine.OutputSchema.Field`
// / `.Kind` / `.KindChoice` / `.KindStringKind`, matching their `swift_name`
// attributes. The flat `PasturaSharedEngine.OutputSchemaField` spelling does not
// exist; measured against the staged simulator slice 2026-08-30.

/// Converts the Kotlin `OutputSchema` carried on a `GenerationRequest` into the
/// Swift ``OutputSchema`` the LLM layer's backends consume.
///
/// **Why this exists.** No converter existed when the Stage-5 `LLMBackend`
/// adapter arrived: the Stage-2 gate spike's scripted backend (retired at S5-5)
/// replayed canned text, so it read the request's `schema` off and never needed
/// one. But the schema is what each real backend translates into its native
/// constrained-decoding mechanism (llama.cpp: a GBNF grammar; Ollama:
/// `format:"json"`), so dropping it at the K/N boundary would silently disable
/// constrained decoding: no compile error, no runtime signal, just free-form
/// output where structured JSON was contracted. ADR-023 S5-2 PR-A, #1647.
extension OutputSchema {

  /// Builds the Swift schema from its Kotlin counterpart, preserving `fields`
  /// order — the primary-first ordering policy is load-bearing for the
  /// streaming UX (see ``OutputSchema`` for why).
  nonisolated init(shared: PasturaSharedEngine.OutputSchema) {
    self.init(fields: shared.fields.map(Field.init(shared:)))
  }

  /// Optional-preserving form of ``init(shared:)`` for the request's nullable
  /// `schema` property. `nil` in means `nil` out — callers read that as "no
  /// constrained decoding", matching `OutputSchema.from(phase:)`.
  nonisolated static func fromShared(_ shared: PasturaSharedEngine.OutputSchema?) -> OutputSchema? {
    shared.map(OutputSchema.init(shared:))
  }
}

extension OutputSchema.Field {
  nonisolated init(shared: PasturaSharedEngine.OutputSchema.Field) {
    self.init(name: shared.name, kind: OutputSchema.Kind(shared: shared.kind))
  }
}

extension OutputSchema.Kind {
  /// A Kotlin sealed class is not switch-exhaustive from Swift — K/N exports it
  /// as an Obj-C class hierarchy, so this can only be an `is` chain and the
  /// compiler cannot tell us when Kotlin gains a third subtype.
  nonisolated init(shared: PasturaSharedEngine.OutputSchema.Kind) {
    if shared is PasturaSharedEngine.OutputSchema.KindChoice {
      self = .choice
    } else if shared is PasturaSharedEngine.OutputSchema.KindStringKind {
      self = .string
    } else {
      // An unrecognised Kind means Kotlin added a subtype this build predates.
      // Degrade to the least-constraining kind rather than trapping: `.string`
      // emits the shared GBNF `string` production, which accepts anything a
      // narrower kind would have accepted, so a stale app keeps generating
      // valid JSON instead of crashing mid-simulation.
      self = .string
    }
  }
}
