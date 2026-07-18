import KMPGateSpike

// ADR-023 §6 gate measurements (i)/(ii)/(iii). Filled in alongside the
// adapters; this entry point exists from the first commit so the package's
// target graph is complete and `swift build` is a real signal.
print("kmp-gate-bench — ADR-023 §6 Stage-2 gate measurements")
print(
  "linked boundary types: \(SharedEngineLinkage.objcRuntimeNames.joined(separator: ", "))")
