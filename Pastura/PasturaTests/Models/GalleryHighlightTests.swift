import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1))) struct GalleryHighlightTests {

  // MARK: - Fixtures

  private static let validJSON = """
    {
      "schema_version": 1,
      "scenario_ref": {
        "id": "asch_conformity_v1",
        "yaml_sha256": "090ef06d9d49ea3a538d33c05299a2b7a45100f6aafa3dfa71da28bd81d13960"
      },
      "source": {
        "model": "gemma-4-e2b-q4-k-m",
        "run_id": "20260806-000253-bd2a",
        "generated_at": "2026-08-06"
      },
      "excerpt": [
        {
          "agent": "サクラA",
          "round": 1,
          "phase": "speak_each",
          "phase_index": 0,
          "source_field": "statement",
          "text": "答えはCです。"
        },
        {
          "agent": "被験者ナオキ",
          "round": 1,
          "phase": "speak_each",
          "phase_index": 0,
          "source_field": "statement",
          "text": "私は基準線と同じ長さの線はBだと思います。"
        }
      ],
      "yaml_hook": {
        "fragment": "  - name: 被験者ナオキ\\n    description: >\\n      素朴な性格。",
        "caption": "サクラの人数を書き換えると、同調圧力の強さが変わる。"
      },
      "teaser": "最終ラウンド、ナオキはBを貫けるのか——結末はアプリで。",
      "window_override": false,
      "content_filter_applied": true
    }
    """

  @Test func decodesFullyValidFixture() throws {
    let highlight = try JSONDecoder().decode(
      GalleryHighlight.self, from: Data(Self.validJSON.utf8))

    #expect(highlight.schemaVersion == 1)
    #expect(highlight.scenarioRef.id == "asch_conformity_v1")
    #expect(
      highlight.scenarioRef.yamlSHA256
        == "090ef06d9d49ea3a538d33c05299a2b7a45100f6aafa3dfa71da28bd81d13960")
    #expect(highlight.source.model == "gemma-4-e2b-q4-k-m")
    #expect(highlight.source.runID == "20260806-000253-bd2a")
    #expect(highlight.source.generatedAt == "2026-08-06")
    #expect(highlight.excerpt.count == 2)
    #expect(highlight.excerpt[0].agent == "サクラA")
    #expect(highlight.excerpt[0].round == 1)
    #expect(highlight.excerpt[0].phase == "speak_each")
    #expect(highlight.excerpt[0].phaseIndex == 0)
    #expect(highlight.excerpt[0].sourceField == "statement")
    #expect(highlight.excerpt[0].text == "答えはCです。")
    #expect(highlight.yamlHook.caption == "サクラの人数を書き換えると、同調圧力の強さが変わる。")
    #expect(highlight.teaser == "最終ラウンド、ナオキはBを貫けるのか——結末はアプリで。")
    #expect(highlight.windowOverride == false)
    #expect(highlight.contentFilterApplied == true)
  }

  /// Fail-closed per ADR-029 Decision 4: an absent `content_filter_applied`
  /// must throw at decode time rather than default to `false` (or `true`).
  @Test func missingContentFilterAppliedThrows() throws {
    var json = try #require(
      JSONSerialization.jsonObject(with: Data(Self.validJSON.utf8)) as? [String: Any])
    json.removeValue(forKey: "content_filter_applied")
    let data = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(GalleryHighlight.self, from: data)
    }
  }

  /// Any other required top-level field missing must also throw — the
  /// schema has no optional fields.
  @Test func missingTeaserThrows() throws {
    var json = try #require(
      JSONSerialization.jsonObject(with: Data(Self.validJSON.utf8)) as? [String: Any])
    json.removeValue(forKey: "teaser")
    let data = try JSONSerialization.data(withJSONObject: json)

    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(GalleryHighlight.self, from: data)
    }
  }

  /// `content_filter_applied: false` must decode successfully as `false` —
  /// whether to hide the section on that basis is the caller's decision
  /// (ADR-029 Decision 4), not the decoder's.
  @Test func contentFilterAppliedFalseDecodes() throws {
    var json = try #require(
      JSONSerialization.jsonObject(with: Data(Self.validJSON.utf8)) as? [String: Any])
    json["content_filter_applied"] = false
    let data = try JSONSerialization.data(withJSONObject: json)

    let highlight = try JSONDecoder().decode(GalleryHighlight.self, from: data)
    #expect(highlight.contentFilterApplied == false)
  }
}
