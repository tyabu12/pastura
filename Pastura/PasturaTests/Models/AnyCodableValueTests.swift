import Foundation
import Testing

@testable import Pastura

@Suite(.timeLimit(.minutes(1)))
struct AnyCodableValueTests {
  @Test func stringRoundTrip() throws {
    let original = AnyCodableValue.string("hello")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
    #expect(decoded == original)
  }

  @Test func arrayRoundTrip() throws {
    let original = AnyCodableValue.array(["topic1", "topic2", "topic3"])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
    #expect(decoded == original)
  }

  @Test func dictionaryRoundTrip() throws {
    let original = AnyCodableValue.dictionary(["majority": "りんご", "minority": "みかん"])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
    #expect(decoded == original)
  }

  @Test func arrayOfDictionariesRoundTrip() throws {
    let original = AnyCodableValue.arrayOfDictionaries([
      ["majority": "りんご", "minority": "みかん"],
      ["majority": "温泉", "minority": "プール"]
    ])
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnyCodableValue.self, from: data)
    #expect(decoded == original)
  }

  @Test func decodingUnsupportedTypeThrows() {
    let json = Data("[1, 2, 3]".utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AnyCodableValue.self, from: json)
    }
  }
}
