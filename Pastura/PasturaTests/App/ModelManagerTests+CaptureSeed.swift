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

      // Pass an explicit progress so the assertion exercises the seam's
      // contract ("force `.downloading` with the given value") rather than
      // coupling to the production default.
      sut.captureSeedDownloadingState(for: descriptor, progress: 0.3)

      #expect(sut.state[descriptor.id] == .downloading(progress: 0.3))
    }
  }
#endif
