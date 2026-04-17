import Foundation

/// Distribution mode for `assign` phases — controls how a source value is mapped
/// to active agents.
///
/// - `all` (default when omitted in YAML): every active agent receives the same
///   round-indexed item from the source. Source must be a flat list of strings or
///   a single string.
/// - `randomOne`: one randomly-chosen agent receives the `minority` value, the
///   rest receive `majority`. Source must be a list of `{majority, minority}`
///   dictionaries (e.g., word wolf topic sets).
nonisolated public enum AssignTarget: String, Codable, Sendable, CaseIterable {
  case all
  case randomOne = "random_one"
}
