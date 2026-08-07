import SwiftUI

/// The curated-highlight section of `GalleryScenarioDetailView` (ADR-029),
/// split into a sibling extension to keep the host file inside SwiftLint's
/// length caps.
///
/// **Static text only.** ADR-029 Decision 6 keeps highlights outside the
/// Phase-3 "Replay gallery" deferral only while this section renders a fixed,
/// authored excerpt with no run / replay / seek affordance of any kind. The
/// edit invitation is copy, not a button — the screen's existing install CTA
/// is the only action.
///
/// Every string sourced from the highlight file is remote content (currently
/// Japanese, on both `en` and `ja` chrome) and must never resolve as a
/// `LocalizedStringKey`. The teaser, the hook's caption, and everything drawn
/// from its fragment — the raw block, and each persona row's name and
/// description — say so explicitly with `Text(verbatim:)`. Only the section's
/// own chrome is localizable — and both of its rendition-dependent strings, the
/// heading and the edit invitation, are chosen per rendition rather than fixed.
/// The excerpt lines reach ``AgentOutputRow`` instead, which is
/// safe for a different reason: it is handed `String` / `Substring`
/// *values*, and the `LocalizedStringKey` overload of `Text.init` binds only to
/// string literals, so a non-literal argument selects the `StringProtocol` one.
extension GalleryScenarioDetailView {

  /// Renders only once the loader has fetched **and** verified a highlight.
  /// Absent, in-flight, and every verification failure alike collapse to
  /// `EmptyView()` — no spinner, no placeholder, no error UI (ADR-029
  /// Decision 4: a failure the user cannot act on is worse than absence).
  @ViewBuilder
  var highlightSection: some View {
    if let highlight = highlightLoader?.highlight {
      // `?? .rawYAML` rather than a second `let`: the loader sets both together,
      // but binding them as a pair would make a missing *rendition* hide the
      // excerpt, teaser and caption too — turning a presentation fallback into a
      // content gate, and a silent one, since no `check=` line would name it.
      // `.rawYAML` is the enum's own answer to "nothing better could be
      // derived", so the section's presence stays keyed on `highlight` alone.
      let rendition = highlightLoader?.hookRendition ?? .rawYAML
      PasturaSection(String(localized: "A glimpse of a real run")) {
        VStack(alignment: .leading, spacing: 16) {
          GalleryHighlightRunFigure(
            excerpt: highlight.excerpt, totalRounds: scenario.rounds)
          teaserLine(highlight.teaser)
          yamlHook(highlight.yamlHook, rendition: rendition)
          editInvitation(rendition)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// One spoiler-free line teasing the outcome — italic + secondary ink so it
  /// reads as a caption on the excerpt rather than another spoken line.
  fileprivate func teaserLine(_ teaser: String) -> some View {
    Text(verbatim: teaser)
      .font(.callout.italic())
      .foregroundStyle(Color.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// What produced the excerpt, plus its caption. The caption and every string
  /// drawn from the fragment are remote content.
  ///
  /// The heading is chosen with the body, never independently: a persona
  /// rendition shows no YAML, so keeping a heading that says "YAML" would
  /// describe something that is not on screen (ADR-029 § Amendment
  /// 2026-08-08).
  fileprivate func yamlHook(
    _ hook: GalleryHighlightYAMLHook, rendition: GalleryHighlightHookRendition
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(GalleryScenarioDetailFormat.hookHeading(for: rendition))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.ink)
      switch rendition {
      case .personas(let entries):
        personaRows(entries)
      case .rawYAML:
        yamlBlock(hook.fragment)
      }
      Text(verbatim: hook.caption)
        .font(.footnote)
        .foregroundStyle(Color.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// The persona fragment drawn in the visual editor's vocabulary.
  ///
  /// Modelled on `ScenarioDetailView+Sections.personasSection(scenario:)` — the
  /// **static** persona list, which is also the screen the reader lands on
  /// after installing, so this shows the same shape their own copy will.
  /// Deliberately *not* `ScenarioEditorView.personasSection`: that one is
  /// `private`, needs a `Form` host, binds to a view model, and is made
  /// entirely of edit affordances.
  ///
  /// ⚠️ **No `Button`, no `onTapGesture`, no `onDelete`.** ADR-029 Decision 6
  /// keeps highlights outside the Phase-3 replay deferral only while this
  /// section is static text, and this is the first thing in the feature that
  /// *looks* like an editable surface — there is nothing to edit here, since
  /// the scenario is not installed yet. Nothing mechanical detects an
  /// affordance being added; this comment is the guard.
  fileprivate func personaRows(_ entries: [GalleryHighlightHookRendition.Entry]) -> some View {
    // No inner container, for two reasons measured on a screenshot. A
    // `bubbleBackground` panel is invisible against this card — the same
    // near-parity `GalleryHighlightRunFigure` works around with a `rule`
    // hairline — and the horizontal padding it needed pushed every row right of
    // the heading above it. The vocabulary source
    // (`ScenarioDetailView+Sections.personasSection`) has no inner container
    // either: dividers carry the structure, and the rows sit on the card.
    // Stated above the builder rather than below it, because the edit this
    // guards against is typing `.background(…)` onto the `VStack`.
    VStack(spacing: 0) {
      // Keyed by offset, not by name: a fragment is curated text and nothing
      // forbids two entries sharing a name.
      ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
        if index > 0 { PasturaRowDivider() }
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: entry.name)
            .font(.headline)
            .foregroundStyle(Color.ink)
          Text(verbatim: entry.description)
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The fragment as a code-style block — what every hook looked like before
  /// `kind` existed, and still the right rendering for one that claims no
  /// structure or that this build cannot read.
  fileprivate func yamlBlock(_ fragment: String) -> some View {
    Text(verbatim: GalleryScenarioDetailFormat.yamlFragmentForDisplay(fragment))
      // Text-style-relative so the code block scales with Dynamic Type
      // alongside the section's prose (a fixed point size would not).
      .font(.system(.caption2, design: .monospaced))
      .foregroundStyle(Color.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        Color.bubbleBackground,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  /// Open-in-app-and-edit invitation (ADR-029 Decision 5). Deliberately says
  /// nothing about submitting a scenario back to the gallery — user
  /// submissions are the Phase 3 marketplace — and adds no run affordance.
  fileprivate func editInvitation(
    _ rendition: GalleryHighlightHookRendition
  ) -> some View {
    Text(GalleryScenarioDetailFormat.hookInvitation(for: rendition))
      .font(.caption)
      .foregroundStyle(Color.muted)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
