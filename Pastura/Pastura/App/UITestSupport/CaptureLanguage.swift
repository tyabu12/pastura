#if DEBUG

  import Foundation

  /// Picks the device-language variant of a **capture fixture** — seeded data
  /// that gets photographed for the App Store (`StoreScreenshotTests`) rather
  /// than rendered from the string catalog.
  ///
  /// Callers pass ``LocaleResolver/deviceDefault(preferredLocalizations:)`` (the
  /// ADR-010 D2 canonical seam), normally as a default argument so tests can pin
  /// the language and stay deterministic across runner locales.
  ///
  /// **Deliberately not `pickLanguage(_:ja:en:)`.** That helper's `default:` arm
  /// returns **ja**, which is right for Engine scenario-language dispatch: its
  /// input is `scenario.engineLanguage`, validator-gated to `{ja, en}`, with ja
  /// as the authoring baseline. Here the input is a *device* locale and the base
  /// locale is **en** — the App Store launch target — so an unrecognized code
  /// must fall back to English, the same arm `LocaleResolver.deviceDefault()`
  /// itself takes. Sharing one helper across the capture fixtures keeps that
  /// fallback from drifting between them.
  ///
  /// Generic over `T` so it serves both `String` fixtures (YAML, display names)
  /// and structured ones (``StoreScoreboardSample/Sample``).
  nonisolated func pickCaptureLanguage<T>(_ language: String, ja: T, en: T) -> T {
    language == "ja" ? ja : en
  }

#endif
