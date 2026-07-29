import SwiftUI

/// A shareable "highlight" image card built from a single agent utterance
/// (issue #1070, Growth A-1).
///
/// The card is rasterized via `ImageRenderer` (see
/// ``HighlightCardImageRenderer``) and handed to the system share sheet, so a
/// memorable line from a simulation can be posted to social media as a
/// self-contained one-shot image — the app's primary organic-growth path.
///
/// Presentation-only by design (ADR-009): it takes already-resolved ``Model``
/// strings, never Engine/Data domain types. Both entry points (the live
/// `SimulationView` transcript and the past-results `ResultDetailView`) build a
/// ``Model`` and render this view off-screen.
///
/// ## Appearance
///
/// The card carries an **explicit** ``colorScheme`` rather than reading
/// `@Environment(\.colorScheme)`. Two reasons, both load-bearing:
/// 1. `ImageRenderer` renders its content in a *default* environment and does
///    NOT inherit the ambient color scheme — an unset card would always
///    rasterize light regardless of the device.
/// 2. The app's `Color.*` aliases are trait-resolving for the 57 paired
///    §2.9 tokens (ADR-028). Reading them here would make each family's colour
///    depend on how `ImageRenderer` happens to resolve a dynamic `UIColor` —
///    which is not contractually tied to the SwiftUI environment, even though
///    both renderers do pin `.environment(\.colorScheme, colorScheme)`.
///    ``HighlightCardPalette`` therefore reads the raw `PasturaPalette` values, which are
///    fixed sRGB, and selects the family itself.
///
/// The same reasoning reaches one level further down. ``SheepAvatar`` used to
/// read the `Color.avatar*` aliases directly, which were fixed until slice 3 of
/// ADR-028 gate 1 paired them; from that point the card's sheep would have
/// resolved to whatever appearance the renderer picked, unpinned by
/// ``HighlightCardPalette`` (which covers six tokens, none of them §2.5). So the
/// card passes its ``colorScheme`` into the avatar as well, and
/// ``SheepAvatarPalette`` selects fixed values from it.
/// The caller captures the device's `@Environment(\.colorScheme)` at the
/// share site and passes it in, so the shared image matches what the user sees.
struct HighlightShareCard: View {

  /// Resolved, display-ready values for the highlight card.
  ///
  /// The failable initializer is the content-safety + visibility guard: it
  /// runs the raw utterance through `ContentFilter` (never trust the caller to
  /// have filtered — the past-results path reads *unfiltered* persisted text,
  /// see #1075) and returns `nil` when nothing visible remains, so the caller
  /// renders nothing rather than an empty card.
  nonisolated struct Model {
    /// Agent display name (verbatim, not localized).
    let agent: String
    /// Avatar color slot, resolved from the agent name + turn position.
    let character: SheepAvatar.Character
    /// The quoted line — filtered and edge-trimmed, guaranteed non-empty.
    let utterance: String
    /// The agent's inner thought (心の声), filtered and edge-trimmed, or `nil`
    /// when absent / filtered-to-empty so the card drops the INNER VOICE
    /// section rather than rendering an empty ornament (#1080).
    let thought: String?
    /// Scenario name, or `nil` to omit the "from …" line.
    let scenarioTitle: String?
    /// Inference model label (e.g. "Gemma 4 E2B"), or `nil` to omit the line.
    let modelName: String?
    /// Burned-in link. Optional so a missing/invalid URL just drops the line.
    let linkURL: URL?

    /// Builds a model, or returns `nil` when the filtered utterance has no
    /// visible content.
    ///
    /// - Parameters:
    ///   - rawUtterance: the display text as read at the call site; it is
    ///     re-filtered here unconditionally.
    ///   - rawThought: the inner-thought text as read at the call site
    ///     (`nil` for phases without a thought). Re-filtered here — like
    ///     `rawUtterance`, persisted thought text is *unfiltered* (#1075), so
    ///     it must be re-filtered before it is burned into a public share
    ///     image (ADR-005). A thought that filters to empty collapses to `nil`
    ///     (utterance-only card); it never drops the whole model.
    ///   - contentFilter: injected so the applied filtering is testable
    ///     (mirrors the production `ContentFilter()` the call sites hold).
    init?(
      agent: String,
      agentPosition: Int?,
      rawUtterance: String,
      rawThought: String?,
      scenarioTitle: String?,
      modelName: String?,
      linkURL: URL?,
      contentFilter: ContentFilter
    ) {
      let filtered = contentFilter.filter(rawUtterance)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !filtered.isEmpty else { return nil }
      self.agent = agent
      self.character = SheepAvatar.Character.forAgent(agent, position: agentPosition)
      self.utterance = filtered
      self.thought = Self.filteredNonEmpty(rawThought, filter: contentFilter)
      self.scenarioTitle = Self.nonEmpty(scenarioTitle)
      self.modelName = Self.nonEmpty(modelName)
      self.linkURL = linkURL
    }

    /// Trims and collapses an optional label to `nil` when it has no visible
    /// content, so an empty scenario title / model id drops its whole line
    /// rather than rendering a stray separator.
    private static func nonEmpty(_ value: String?) -> String? {
      guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !trimmed.isEmpty
      else { return nil }
      return trimmed
    }

    /// Runs an optional raw thought through the content filter and collapses a
    /// blocked-to-empty / whitespace-only result to `nil`. Same `ContentFilter`
    /// pass as the utterance (a redaction to visible content like "***" is
    /// kept — only whitespace-emptiness drops the thought), so the card takes
    /// the utterance-only layout rather than rendering an empty INNER VOICE
    /// section.
    private static func filteredNonEmpty(_ raw: String?, filter: ContentFilter) -> String? {
      guard let raw else { return nil }
      let filtered = filter.filter(raw)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return filtered.isEmpty ? nil : filtered
    }
  }

  let model: Model
  /// Explicit appearance — see the type doc for why this is not read from the
  /// environment.
  ///
  /// Non-optional with a `.light` default, which is the shape
  /// ``SheepAvatar/colorScheme`` explicitly forbids for itself. The two are not
  /// in conflict: this card is **never** ambient — all its construction sites
  /// (`HighlightCardImageRenderer`, `StoryShareSheet`) pass an appearance
  /// explicitly — whereas the avatar is ambient at ten of its eleven, so a
  /// silent default there would pin the app to light.
  var colorScheme: ColorScheme = .light

  /// Point size of the square card. `ImageRenderer` scales this up (×3) to the
  /// exported 1080 px asset. Kept as a constant so the layout math and the
  /// renderer's `proposedSize` agree.
  static let side: CGFloat = 360

  private var palette: HighlightCardPalette { colorScheme == .dark ? .dark : .light }

  var body: some View {
    ZStack {
      palette.background
      // The single "light leak" the design system permits (§1: one glow only).
      // A soft moss radial in the top-right — quiet, never washing the text.
      RadialGradient(
        gradient: Gradient(colors: [
          palette.moss.opacity(colorScheme == .dark ? 0.10 : 0.14),
          palette.moss.opacity(0)
        ]),
        center: .center, startRadius: 0, endRadius: 120
      )
      .frame(width: 240, height: 240)
      .offset(x: 120, y: -120)

      VStack(alignment: .leading, spacing: 0) {
        header
        Spacer().frame(height: 15)
        quote
        Spacer(minLength: 22)
        footer
      }
      .padding(28)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: Self.side, height: Self.side)
    .clipped()
  }

  private var header: some View {
    HStack(spacing: 12) {
      SheepAvatar(character: model.character, size: 46, colorScheme: colorScheme)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.agent)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(palette.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        if let modelName = model.modelName {
          Text(modelName)
            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
    }
  }

  private var quote: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        // Serif open-quote ornament — a deliberate off-note against the sans
        // body, marking "this is a quotation". Fixed height so it doesn't pad
        // the utterance below it.
        Text(verbatim: "\u{201C}")
          .font(.system(size: 52, design: .serif))
          .foregroundStyle(palette.moss.opacity(0.45))
          .frame(height: 26, alignment: .top)
        Text(model.utterance)
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(palette.ink)
          .lineSpacing(6)
          // Long utterances are quoted as a *fragment* and ellipsize (#1070
          // truncation rule). With a thought below, cap the spoken line
          // tighter so both blocks fit the 360pt square; utterance-only keeps
          // the original 5-line budget. Over-budget content clips gracefully
          // via the card's `.clipped()` — the card is a highlight, not a full
          // transcript.
          .lineLimit(model.thought == nil ? 5 : 3)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let thought = model.thought {
        thoughtSection(thought)
      }
    }
  }

  /// The 心の声 (INNER VOICE) block beneath the utterance (#1080). Echoes the
  /// transcript row's inner-voice visual language (design-system §5.2 — moss
  /// left rule + mono UPPER tag + muted italic body) so the shared card reads
  /// in the same idiom as the app. Line-capped for the square; long thoughts
  /// ellipsize.
  private func thoughtSection(_ thought: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 1.25, style: .continuous)
        .fill(palette.moss.opacity(0.5))
        .frame(width: 2.5)
      VStack(alignment: .leading, spacing: 4) {
        // Reuses the transcript row's "INNER VOICE" catalog key (see
        // `AgentOutputRow.thoughtToggleHeader`) — same literal, no new key.
        Text(String(localized: "INNER VOICE"))
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .tracking(0.6)
          .foregroundStyle(palette.moss)
        Text(thought)
          .font(.system(size: 15, weight: .regular))
          .italic()
          .foregroundStyle(palette.inkSecondary)
          .lineSpacing(4)
          .lineLimit(3)
          .truncationMode(.tail)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 0) {
      Rectangle()
        .fill(palette.rule)
        .frame(height: 1)
        .padding(.bottom, 14)
      if let scenarioTitle = model.scenarioTitle {
        Text(scenarioLine(scenarioTitle))
          .font(.system(size: 12.5))
          .foregroundStyle(palette.inkSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.bottom, 16)
      }
      HStack(spacing: 0) {
        HStack(spacing: 9) {
          Image("BrandIcon")
            .resizable()
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
          Text(verbatim: "Pastura")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(palette.ink)
        }
        Spacer(minLength: 8)
        if let link = model.linkURL {
          Text(verbatim: link.host ?? "pastura.app")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(palette.moss)
        }
      }
    }
  }

  /// "from “<scenario>”" — localized; ja renders 「シナリオ「%@」より」.
  private func scenarioLine(_ title: String) -> String {
    String(format: String(localized: "from “%@”"), title)
  }
}

/// Light / night token pair the card selects between by ``HighlightShareCard/colorScheme``.
/// Reads the raw `PasturaPalette` values rather than the `Color.*` aliases, so
/// the palette never drifts from the app's canonical colors *and* each family
/// stays a fixed appearance. **Load-bearing**: eight of those aliases became
/// trait-resolving in ADR-028, so `Color.ink` here would mean "the device's
/// appearance" and collapse `light` and `dark` into the same thing — which
/// nothing else would catch, since `ImageRenderer` output is not asserted
/// anywhere (ADR-009 rules out snapshot tests).
/// Internal, not `private`, so `HighlightShareCardPaletteTests` can pin each
/// family to its raw palette values — the only mechanical detector that an
/// alias has not crept back in here (ADR-009 rules out the snapshot test that
/// would otherwise be the only one). Comparing two `Color` values is
/// logic-extraction unit testing, which ADR-009 permits.
struct HighlightCardPalette {
  let background: Color
  let ink: Color
  let inkSecondary: Color
  let muted: Color
  let rule: Color
  let moss: Color

  static let light = HighlightCardPalette(
    background: PasturaPalette.screenBackground.color,
    ink: PasturaPalette.ink.color,
    inkSecondary: PasturaPalette.inkSecondary.color,
    muted: PasturaPalette.muted.color,
    rule: PasturaPalette.rule.color,
    moss: PasturaPalette.moss.color)

  static let dark = HighlightCardPalette(
    background: PasturaPalette.nightBackground.color,
    ink: PasturaPalette.nightInk.color,
    inkSecondary: PasturaPalette.nightInkSecondary.color,
    muted: PasturaPalette.nightMuted.color,
    rule: PasturaPalette.nightRule.color,
    moss: PasturaPalette.nightMoss.color)
}

/// The long-press menu content for the highlight share affordance — currently a
/// single "Share as Card" action, factored out so that if more per-row actions
/// arrive, ``AgentOutputRow``'s visible affordance can switch from its direct
/// share button to a `Menu` rendering this same builder without the two
/// surfaces drifting.
@ViewBuilder
func highlightShareMenuItems(action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Label(String(localized: "Share as Card"), systemImage: "square.and.arrow.up")
  }
}

/// Adds a "Share as Card" context menu when `action` is non-nil; a nil action
/// leaves the view untouched (no empty long-press menu on rows without a share
/// handler). Shared by both highlight entry points (#1070): the live transcript
/// row and the past-results row. ``AgentOutputRow`` (#1080) pairs this
/// long-press menu with a visible direct share button for discoverability.
struct HighlightShareContextMenu: ViewModifier {
  let action: (() -> Void)?

  func body(content: Content) -> some View {
    if let action {
      content.contextMenu {
        highlightShareMenuItems(action: action)
      }
    } else {
      content
    }
  }
}

#Preview("Highlight card — light / dark") {
  let filter = ContentFilter()
  return HStack(spacing: 20) {
    if let model = HighlightShareCard.Model(
      agent: "Bob", agentPosition: 1,
      rawUtterance: "正直に言うと、僕は最初から君を裏切るつもりだったんだ。でも今は…少しだけ後悔しているよ。",
      rawThought: "本当は協力したかった。でも先に裏切られるのが怖くて、こちらから裏切ってしまった。",
      scenarioTitle: "囚人のジレンマ", modelName: "Gemma 4 E2B",
      linkURL: LocalizedPublicPages.sharedScenario(id: "prisoners_dilemma"),
      contentFilter: filter) {
      HighlightShareCard(model: model, colorScheme: .light)
    }
    if let model = HighlightShareCard.Model(
      agent: "Carol", agentPosition: 2,
      rawUtterance: "Honestly? I planned to betray you from the very first round.",
      rawThought: "I keep telling myself it was just strategy. It wasn’t.",
      scenarioTitle: "The Prisoner’s Dilemma", modelName: "Gemma 4 E2B",
      linkURL: LocalizedPublicPages.sharedScenario(id: "prisoners_dilemma"),
      contentFilter: filter) {
      HighlightShareCard(model: model, colorScheme: .dark)
    }
  }
  .padding()
}
