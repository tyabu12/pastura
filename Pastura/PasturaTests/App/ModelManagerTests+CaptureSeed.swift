import Foundation
import Testing

@testable import Pastura

// The capture seam is `#if DEBUG`-only (motion-capture tooling), so its test
// must be gated the same way — otherwise a Release test compile would fail on
// the missing symbol. Sibling-file extension on the existing suite (not a new
// `@Suite`) per .claude/rules/testing.md — a parallel suite would race the
// original on shared Application Support / Caches paths.
#if DEBUG
  extension ModelManagerTests {
    @Test("captureSeedDownloadingState forces the descriptor into .downloading")
    func captureSeedForcesDownloadingState() {
      let descriptor = makeTestDescriptor()
      let sut = makeSUT(catalog: [descriptor])
      // Precondition: a fresh manager seeds every descriptor `.checking`.
      #expect(sut.state[descriptor.id] == .checking)

      sut.captureSeedDownloadingState(for: descriptor)

      #expect(sut.state[descriptor.id] == .downloading(progress: 0.4))
    }
  }
#endif
