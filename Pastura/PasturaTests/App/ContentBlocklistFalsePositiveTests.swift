import Foundation
import Testing

@testable import Pastura

/// Data-driven guard suite for the expanded ContentBlocklist (90 patterns, commit 6a352a4).
///
/// Pins the curation invariants that were validated during the blocklist-expansion
/// review: min-length for ASCII terms, benign-corpus cleanliness, positive
/// sanity samples, partition postconditions not already covered by
/// ``ContentBlocklistTests``, and bundled-preset safety.
///
/// Does NOT duplicate assertions from ``ContentBlocklistTests``, which owns
/// the cardinality canaries (entries/output 90, input 77), bundle-shape
/// checks, decode failure modes, and the output-superset invariant.
@Suite(.timeLimit(.minutes(1)))
struct ContentBlocklistFalsePositiveTests {

  // MARK: - 1. Min-length rule (all-ASCII terms)

  // Exception list: ASCII terms that are approved despite being < 4 characters.
  // Empty allowlist — structure here so a future exception is a one-line addition.
  private let asciiMinLengthExceptions: Set<String> = []

  @Test func allASCIITermsAreAtLeastFourCharacters() {
    let bundle = Bundle(for: DatabaseManager.self)
    let entries = ContentBlocklist.entries(from: bundle)
    var violations: [(term: String, length: Int)] = []
    for entry in entries {
      let term = entry.term
      // Only enforce on all-ASCII terms — Japanese/non-Latin scripts use
      // ideographic units where a 2-character term is already a specific word
      // (e.g. "殺す") and substring-match false positives are far less likely.
      guard term.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
      guard !asciiMinLengthExceptions.contains(term) else { continue }
      if term.count < 4 {
        violations.append((term: term, length: term.count))
      }
    }
    #expect(
      violations.isEmpty,
      "ASCII terms shorter than 4 chars are false-positive magnets (e.g. 'kys' ⊂ 'skyscraper'). Violations: \(violations)"
    )
  }

  // MARK: - 2. Benign corpus stays clean

  // MARK: English benign phrases

  @Test func benignEnglishPhrasesPassOutputFilter() {
    let filter = ContentFilter()
    let phrases = [
      "class",
      "grape",
      "document",
      "assassin",
      "skyscraper",
      "niggardly",
      "cutwater",
      "a chink in the armor",
      // Accepted collisions, intentionally OMITTED from this corpus
      // (see docs/blocklist/README.md § Accepted collisions): "Scunthorpe
      // United" (⊃ cunt), "milfoil" (⊃ milf), "swanker" (⊃ wanker). The
      // curation decision keeps those terms and accepts the rare false
      // positive. If a term is ever removed, re-add its phrase here.
      "analysis",
      "therapist"
    ]
    for phrase in phrases {
      let result = filter.filter(phrase)
      #expect(
        result == phrase,
        "Output filter wrongly modified '\(phrase)' → '\(result)'"
      )
    }
  }

  @Test func benignEnglishPhrasesPassInputCheck() {
    let inputPatterns = ContentBlocklist.inputPatterns
    let phrases = [
      "class",
      "grape",
      "document",
      "assassin",
      "skyscraper",
      "niggardly",
      "cutwater",
      "a chink in the armor",
      // Accepted collisions omitted — see benignEnglishPhrasesPassOutputFilter
      "analysis",
      "therapist"
    ]
    for phrase in phrases {
      let matched = inputPatterns.first { pattern in
        phrase.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
      #expect(
        matched == nil,
        "Input check wrongly flagged '\(phrase)' (matched pattern: '\(matched ?? "?")')"
      )
    }
  }

  // MARK: Japanese benign phrases

  @Test func benignJapanesePhrasePassOutputFilter() {
    let filter = ContentFilter()
    let phrases = [
      "パチンコ",
      "ちびっこ",
      "傍らに立つ",
      "かたわらの本",
      "指値で注文",
      "さしね注文",
      "楽しいね",
      "プレイプラン",
      "応援交流",
      "粘土人形",
      "エタノール",
      "アスペクト比",
      "非人道的",
      "唖然とした",
      "ちょんまげ",
      "ホモサピエンス",
      "エッチング",
      "鎮魂歌",
      "東シナ海",
      // Comedy-preset mild insults — deliberately NOT added to blocklist
      "クソゲー",
      "ボケて",
      "天然ボケ",
      "バカヤロー"
    ]
    for phrase in phrases {
      let result = filter.filter(phrase)
      #expect(
        result == phrase,
        "Output filter wrongly modified '\(phrase)' → '\(result)'"
      )
    }
  }

  @Test func benignJapanesePhrasesPassInputCheck() {
    let inputPatterns = ContentBlocklist.inputPatterns
    let phrases = [
      "パチンコ",
      "ちびっこ",
      "傍らに立つ",
      "かたわらの本",
      "指値で注文",
      "さしね注文",
      "楽しいね",
      "プレイプラン",
      "応援交流",
      "粘土人形",
      "エタノール",
      "アスペクト比",
      "非人道的",
      "唖然とした",
      "ちょんまげ",
      "ホモサピエンス",
      "エッチング",
      "鎮魂歌",
      "東シナ海",
      // Comedy-preset mild insults — deliberately NOT added to blocklist
      "クソゲー",
      "ボケて",
      "天然ボケ",
      "バカヤロー"
    ]
    for phrase in phrases {
      let matched = inputPatterns.first { pattern in
        phrase.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }
      #expect(
        matched == nil,
        "Input check wrongly flagged '\(phrase)' (matched pattern: '\(matched ?? "?")')"
      )
    }
  }

  // MARK: - 3. Positive sanity

  @Test func outputFilterCatchesBukkake() {
    let filter = ContentFilter()
    let result = filter.filter("The art technique is bukkake ink wash")
    #expect(result.contains("***"), "Output filter must catch 'bukkake'")
    // Only the matched term is replaced — surrounding benign text survives.
    #expect(result.contains("ink wash"), "Filter must not over-mask beyond the term")
  }

  @Test func inputCheckFlagsKoukanJa() {
    // "強姦" is in the sexual category → present in inputPatterns.
    let inputPatterns = ContentBlocklist.inputPatterns
    let matched = inputPatterns.first { pattern in
      "強姦シーン".range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
    #expect(matched != nil, "Input check must flag '強姦'")
  }

  @Test func outputFilterCatchesDiacriticFoldedVariant() {
    // "shït" — diacriticInsensitive folds ï→i → matches "shit"
    let filter = ContentFilter()
    let result = filter.filter("What shït is this")
    #expect(
      result.contains("***"), "Output filter must catch diacritic-folded 'shït' via 'shit' pattern")
  }

  // MARK: - 4. Partition invariants post-expansion

  @Test func inputPatternsIsNonEmpty() {
    // Guards the §10.1 empty-partition preconditionFailure path.
    #expect(!ContentBlocklist.inputPatterns.isEmpty)
  }

  @Test func inputPatternsContainNoViolenceCategory() {
    let bundle = Bundle(for: DatabaseManager.self)
    let entries = ContentBlocklist.entries(from: bundle)
    let violenceTerms = Set(
      entries
        .filter { $0.contentCategory == .violence }
        .map(\.term)
    )
    for term in ContentBlocklist.inputPatterns {
      #expect(
        !violenceTerms.contains(term),
        "inputPatterns must not contain violence-category term '\(term)' (ADR-005 §10.1)"
      )
    }
  }

  // Cardinality canaries (entries/output == 90, input == 77) live in
  // ContentBlocklistTests — not duplicated here.

  // MARK: - 5. Bundled presets survive input validation

  @Test func bundledPresetsPassInputValidation() throws {
    let bundle = Bundle(for: DatabaseManager.self)
    let inputPatterns = ContentBlocklist.inputPatterns
    var failedPresets: [(name: String, matchedPattern: String)] = []

    for fileName in PresetLoader.presetFileNames {
      guard let url = bundle.url(forResource: fileName, withExtension: "yaml") else {
        // Missing file is caught by PresetLoaderTests.presetYAMLsAreParseable
        continue
      }
      let rawText = try String(contentsOf: url, encoding: .utf8)
      // Full-raw-text scan is a superset of §4.3 field-wise validation —
      // passing here implies the user can re-save the preset without triggering
      // ScenarioContentValidator on any field.
      if let matched = inputPatterns.first(where: { pattern in
        rawText.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }) {
        failedPresets.append((name: fileName, matchedPattern: matched))
      }
    }

    #expect(
      failedPresets.isEmpty,
      "Bundled presets contain input-blocked terms: \(failedPresets.map { "\($0.name) matched '\($0.matchedPattern)'" }.joined(separator: ", "))"
    )
  }

  // MARK: - 6. Bundled demo replays survive the OUTPUT filter

  /// `Resources/DemoReplays/*_demo.yaml` are canned playback content shown
  /// during model download. They flow through the output path, so the
  /// output filter would mask any blocked term to `***` and corrupt the
  /// curated demo. They must therefore be clean against the FULL pattern
  /// set (``ContentBlocklist/outputPatterns`` — all 90, incl. `violence`).
  ///
  /// This pins README "Screening pipeline" step 4's "all patterns vs
  /// replays" clause, which nothing else covered: ``BundledDemoReplaySource``
  /// validates SHA / schema / preset-ref drift, not blocklist content.
  ///
  /// Authored content (presets, `docs/gallery/*.yaml`) deliberately uses a
  /// DIFFERENT screen — the INPUT partition (violence-excluded) — because it
  /// is editable / re-savable and the curated ethics scenarios legitimately
  /// contain violence topic words (`殺人事件`, `人を殺す選択`). That contract is
  /// pinned by ``bundledPresetsPassInputValidation`` (above) and
  /// `GallerySeedYAMLTests.allSeedScenariosPassInputValidator`. Scanning
  /// those files against `outputPatterns` would (correctly) flag the
  /// violence vocabulary, so it is NOT done here.
  @Test func bundledDemoReplaysPassOutputFilter() throws {
    let bundle = Bundle(for: DatabaseManager.self)
    let outputPatterns = ContentBlocklist.outputPatterns

    // Mirror BundledDemoReplaySource.enumerateDemoYAMLs: the bundle root is
    // flat, so enumerate every *.yaml and keep `_demo`-suffixed stems.
    let demoURLs = (bundle.urls(forResourcesWithExtension: "yaml", subdirectory: nil) ?? [])
      .filter {
        $0.deletingPathExtension().lastPathComponent
          .hasSuffix(BundledDemoReplaySource.demoFilenameSuffix)
      }

    // Canary: a broken enumeration must not let this test vacuously pass.
    #expect(
      !demoURLs.isEmpty,
      "No *_demo.yaml found in the test bundle — enumeration likely broke")

    var failures: [(name: String, matchedPattern: String)] = []
    for url in demoURLs {
      // Deliberate divergence from production's silent `try?` skip: an
      // unreadable bundled demo is a real problem for a safety guard, so
      // throw here rather than letting it slip past unscanned.
      let rawText = try String(contentsOf: url, encoding: .utf8)
      if let matched = outputPatterns.first(where: { pattern in
        rawText.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) != nil
      }) {
        failures.append((name: url.lastPathComponent, matchedPattern: matched))
      }
    }

    #expect(
      failures.isEmpty,
      "Bundled demo replays contain output-blocked terms (would be masked to *** during playback): \(failures.map { "\($0.name) matched '\($0.matchedPattern)'" }.joined(separator: ", "))"
    )
  }
}
