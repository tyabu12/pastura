import SwiftUI

/// A sheep-head avatar used in the demo replay chat rows and simulation view.
///
/// Rendered as pure SwiftUI shapes — no image assets — so it scales cleanly
/// to any ``size`` and costs nothing at bundle time.
///
/// ```swift
/// SheepAvatar(character: .alice)               // 42 pt default
/// SheepAvatar(character: .dave, size: 32)      // smaller variant
/// ```
public struct SheepAvatar: View {

  /// The four named sheep characters, each with a distinct wool color.
  public enum Character: CaseIterable {
    /// Alice — cream wool. Gentle first voice.
    case alice
    /// Bob — sage wool. Agreeable / calm.
    case bob
    /// Carol — pink wool. Observer.
    case carol
    /// Dave — slate wool. Wolf / central figure.
    case dave
  }

  public let character: Character
  public var size: CGFloat = 48

  /// Top of the visible sheep silhouette expressed as a fraction of
  /// `size`. The outer wool-body circle has center `y = 15` and
  /// radius `8` in the 28-unit viewBox (see ``body``), so the topmost
  /// visible pixel sits at `y = 7`. Consumers aligning the sheep's
  /// *visible* top with a sibling text baseline (e.g. the agent-name
  /// row in `AgentOutputRow`) can pass this value through
  /// `.alignmentGuide(.top) { _ in ... }`.
  ///
  /// Kept on the component so the `y = 7` invariant lives next to the
  /// wool-circle geometry that encodes it — mirrors `DogMark`'s
  /// `visibleTopInset(forSize:)` pattern.
  ///
  /// `nonisolated` because `.alignmentGuide(.top)` takes a `@Sendable`
  /// closure under Swift 6's stricter inference; without it the call
  /// crosses MainActor isolation and warns at the call site.
  nonisolated public static func visibleTopInset(forSize size: CGFloat) -> CGFloat {
    size * 7.0 / 28.0
  }

  public var body: some View {
    Canvas { ctx, canvasSize in
      // All geometry is expressed as fractions of the 28-unit SVG viewBox.
      // Multiplying by `unit` maps viewBox coordinates to canvas points.
      let unit = canvasSize.width / 28

      // --- Wool body (five circles forming a cloud silhouette) ---
      let bodyColor = character.bodyColor
      let woolCircles: [WoolCircle] = [
        WoolCircle(centerX: 14, centerY: 15, radius: 8),
        WoolCircle(centerX: 9, centerY: 13, radius: 3.2),
        WoolCircle(centerX: 19, centerY: 13, radius: 3.2),
        WoolCircle(centerX: 11, centerY: 18, radius: 3),
        WoolCircle(centerX: 17, centerY: 18, radius: 3)
      ]
      for circle in woolCircles {
        let path = Path(
          ellipseIn: CGRect(
            x: (circle.centerX - circle.radius) * unit,
            y: (circle.centerY - circle.radius) * unit,
            width: circle.radius * 2 * unit,
            height: circle.radius * 2 * unit))
        ctx.fill(path, with: .color(bodyColor))
      }

      // --- Face oval (character-specific darker shade) ---
      let facePath = Path(
        ellipseIn: CGRect(
          x: (14 - 4) * unit, y: (15.5 - 4.2) * unit,
          width: 8 * unit, height: 8.4 * unit))
      ctx.fill(facePath, with: .color(character.faceColor))

      // --- Eyes (two dark circles) ---
      let eyeColor = Color.avatarEye
      for eyeCenterX in [CGFloat(12.6), 15.4] {
        let eyePath = Path(
          ellipseIn: CGRect(
            x: (eyeCenterX - 0.7) * unit, y: (14.8 - 0.7) * unit,
            width: 1.4 * unit, height: 1.4 * unit))
        ctx.fill(eyePath, with: .color(eyeColor))
      }

      // --- Highlight dot (top-left of face; adds cartoon sheen) ---
      let highlightPath = Path(
        ellipseIn: CGRect(
          x: (11.6 - 0.5) * unit, y: (13.5 - 0.5) * unit,
          width: 1.0 * unit, height: 1.0 * unit))
      ctx.fill(highlightPath, with: .color(Color.avatarHighlight))

      // --- Horns (two short curved strokes) ---
      let hornColor = character.hornColor
      var leftHorn = Path()
      leftHorn.move(to: CGPoint(x: 10.5 * unit, y: 11.5 * unit))
      leftHorn.addQuadCurve(
        to: CGPoint(x: 11 * unit, y: 9.5 * unit),
        control: CGPoint(x: 10 * unit, y: 10 * unit))
      ctx.stroke(
        leftHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: unit, lineCap: .round))

      var rightHorn = Path()
      rightHorn.move(to: CGPoint(x: 17.5 * unit, y: 11.5 * unit))
      rightHorn.addQuadCurve(
        to: CGPoint(x: 17 * unit, y: 9.5 * unit),
        control: CGPoint(x: 18 * unit, y: 10 * unit))
      ctx.stroke(
        rightHorn, with: .color(hornColor),
        style: StrokeStyle(lineWidth: unit, lineCap: .round))
    }
    .frame(width: size, height: size)
    .accessibilityLabel(character.accessibilityLabel)
  }

  private struct WoolCircle {
    let centerX: CGFloat
    let centerY: CGFloat
    let radius: CGFloat
  }
}

// MARK: - Character helpers

extension SheepAvatar.Character {

  /// Resolves an agent to a ``SheepAvatar/Character`` for avatar rendering.
  ///
  /// ## Resolution order
  ///
  /// 1. **Position (preferred):** when `position` is non-nil, returns
  ///    `allCases[position % 4]`. Scenarios with ≤4 agents get distinct
  ///    colors by construction (pigeonhole — 4 avatar characters and
  ///    at most 4 slots), which matters much more than matching the
  ///    agent's name to a demo-replay canonical color. Wrap-around
  ///    at position ≥ 4 is accepted collision.
  /// 2. **Direct name match:** for the four demo-replay canonical
  ///    names (`Alice` / `Bob` / `Carol` / `Dave`, case-insensitive,
  ///    trimmed), returns the matching character. Preserves the
  ///    demo's hand-curated avatar → name pairing when no position
  ///    context is available (e.g., pre-#171 call sites, previews).
  /// 3. **UTF-8 byte-sum fallback:** for any other name with no
  ///    position, a weak deterministic hash lands in one of the four
  ///    buckets. Same input → same output across runs and processes
  ///    (`String.hashValue` was rejected because Swift randomizes
  ///    hash seeds per process — avatar colors would flicker between
  ///    app launches).
  ///
  /// ## Why position wins
  ///
  /// Name-based assignment has a hidden collision risk: two unrelated
  /// agents may sum to the same bucket, so users see two "same-color
  /// sheep" agents even with only 2-3 scenario participants. Position-
  /// based assignment eliminates collisions up to the 4-character
  /// avatar palette size (design-system.md §2.5), at the cost of
  /// losing the "Alice → alice-cream" convention for scenarios whose
  /// agents *happen* to match canonical names. The trade is worth it
  /// for arbitrary user-authored scenarios; callers that know the
  /// agent's canonical name can still omit `position` and fall
  /// through to step 2.
  public static func forAgent(
    _ name: String, position: Int? = nil
  ) -> SheepAvatar.Character {
    let cases = SheepAvatar.Character.allCases
    if let position {
      // Modulo gates wrap-around for 5+ agents; collisions there are
      // accepted (there are only 4 avatar variants).
      return cases[((position % cases.count) + cases.count) % cases.count]
    }
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalized {
    case "alice": return .alice
    case "bob": return .bob
    case "carol": return .carol
    case "dave": return .dave
    default:
      let sum = normalized.utf8.reduce(0) { $0 &+ Int($1) }
      return cases[sum % cases.count]
    }
  }

  /// Wool / body fill — matches `Color.avatarBodyAlice/Bob/Carol/Dave`.
  var bodyColor: Color {
    switch self {
    case .alice: return Color.avatarBodyAlice
    case .bob: return Color.avatarBodyBob
    case .carol: return Color.avatarBodyCarol
    case .dave: return Color.avatarBodyDave
    }
  }

  /// Face oval fill — matches `Color.avatarFaceAlice/Bob/Carol/Dave`.
  var faceColor: Color {
    switch self {
    case .alice: return Color.avatarFaceAlice
    case .bob: return Color.avatarFaceBob
    case .carol: return Color.avatarFaceCarol
    case .dave: return Color.avatarFaceDave
    }
  }

  /// Horn stroke color — matches `Color.avatarHornAlice/Bob/Carol/Dave`.
  var hornColor: Color {
    switch self {
    case .alice: return Color.avatarHornAlice
    case .bob: return Color.avatarHornBob
    case .carol: return Color.avatarHornCarol
    case .dave: return Color.avatarHornDave
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .alice: return "Alice"
    case .bob: return "Bob"
    case .carol: return "Carol"
    case .dave: return "Dave"
    }
  }
}

// MARK: - Previews

#Preview("All characters") {
  HStack(spacing: 16) {
    ForEach(SheepAvatar.Character.allCases, id: \.accessibilityLabel) { character in
      VStack(spacing: 4) {
        SheepAvatar(character: character)
        Text(character.accessibilityLabel)
          .textStyle(Typography.captionName)
          .foregroundStyle(Color.inkSecondary)
      }
    }
  }
  .padding()
  .background(Color.screenBackground)
}

#Preview("Multiple sizes") {
  HStack(spacing: 20) {
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 32)
      Text("32").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 42)
      Text("42").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
    VStack(spacing: 4) {
      SheepAvatar(character: .alice, size: 56)
      Text("56").textStyle(Typography.captionName).foregroundStyle(Color.muted)
    }
  }
  .padding()
  .background(Color.screenBackground)
}
