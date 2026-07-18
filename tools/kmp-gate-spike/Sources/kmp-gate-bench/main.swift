import Foundation
import KMPGateSpike

// ADR-023 §6 Stage-2 gate measurements (i)/(ii)/(iii). (iv) is a documented
// evaluation with no code, and (v) is discharged by the golden-JSON parity
// suite in `shared/models` — see the package README's measurement table.
//
// Run from the repository root: the shim scan resolves source paths relative
// to the working directory and errors out rather than reporting a zero.

let sourceRoots = [
  "tools/kmp-gate-spike/Sources/KMPGateSpike",
  "tools/kmp-gate-spike/Tests/KMPGateSpikeTests"
]

print("kmp-gate-bench — ADR-023 §6 Stage-2 gate measurements")
print("linked boundary types: \(SharedEngineLinkage.objcRuntimeNames.joined(separator: ", "))")
print("")

// MARK: - (i) / (iii)

do {
  let inventory = try ShimInventory.scan(roots: sourceRoots)

  print("(i)/(iii) K/N boundary ergonomics — shim budget: \(inventory.total) total")
  print("")
  for category in inventory.categories {
    print("  \(category.name): \(category.count)")
    print("    why: \(category.rationale.replacingOccurrences(of: "\n", with: " "))")
    for hit in category.hits {
      print("    - \(hit.file):\(hit.line)  \(hit.text)")
    }
    print("")
  }
  print(
    """
      Not counted, because it is a burden rather than a countable construct:
      Kotlin/Native does not export default arguments, so every `Scenario` must
      be built with all 12 parameters spelled out (see `Scenario.benchSpeakAll`).

      Threading clause: evidenced by the Pattern 6 probe, not re-derived here —
      `Tests/KMPGateSpikeTests/PatternSixProbeTests.swift`.
    """)
  print("")
} catch {
  FileHandle.standardError.write(Data("(i)/(iii) FAILED: \(error)\n".utf8))
  exit(1)
}

// MARK: - (ii)

do {
  let result = try await RelayBenchmark.run()

  func format(_ duration: Duration) -> String {
    let micros =
      Double(duration.components.seconds) * 1e6
      + Double(duration.components.attoseconds) / 1e12
    return String(format: "%.1f µs", micros)
  }

  print("(ii) inference-boundary relay — macOS host")
  print("")
  print(
    "  run with \(result.chunksPerShortRun) chunks: "
      + "best \(format(result.shortScriptRun.best)), "
      + "median \(format(result.shortScriptRun.median))")
  print(
    "  run with \(result.chunksPerLongRun) chunks: "
      + "best \(format(result.longScriptRun.best)), "
      + "median \(format(result.longScriptRun.median))")
  if let perChunk = result.perChunkOverhead, let ceiling = result.impliedCeilingTokensPerSecond {
    print("  → per-chunk crossing overhead: \(format(perChunk))")
    print(
      String(
        format: "  → implied ceiling if crossing were the only cost: %.0f tok/s", ceiling))
    print("    (real generation runs at 10–50 tok/s — ADR-023 §5.2)")
  } else {
    print("  → per-chunk crossing overhead: unresolved — the two runs did not separate")
    print("    (host too noisy at this sample count; re-run before quoting a figure)")
  }
  print("")
  print(
    "  suspension relay round trip: "
      + "best \(format(result.suspensionRoundTrip.best)), "
      + "median \(format(result.suspensionRoundTrip.median))")
  print("    resume() → relay task → notifyLLMResumed() → re-issued call")
  print("")
} catch {
  FileHandle.standardError.write(Data("(ii) FAILED: \(error)\n".utf8))
  exit(1)
}

print("(iv) SKIE-vs-vanilla: documented evaluation only — see README.")
print("(v) kotlinx.serialization parity: shared/models SwiftGoldenParityTests.")
