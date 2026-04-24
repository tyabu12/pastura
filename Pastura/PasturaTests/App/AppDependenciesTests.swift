import Foundation
import Testing

@testable import Pastura

// Tests the active-model switch surface on AppDependencies. The rest of
// the container is thin wiring over DatabaseManager + repository types,
// which get their own tests; this suite focuses on the one mutator added
// for multi-model UI (`regenerateLLMService(_:)`).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AppDependenciesTests {

  @Test func regenerateLLMServiceSwapsInstance() throws {
    let initial = MockLLMService(responses: [])
    let deps = try AppDependencies.inMemory(llmService: initial)
    #expect(
      deps.llmService as AnyObject === initial as AnyObject,
      "sanity: initial service wired")

    let replacement = MockLLMService(responses: [])
    deps.regenerateLLMService(replacement)

    #expect(deps.llmService as AnyObject === replacement as AnyObject)
    #expect(
      deps.llmService as AnyObject !== initial as AnyObject,
      "old instance must be dropped so native resources can free")
  }

  @Test func regenerateLLMServiceDoesNotTouchOtherDependencies() throws {
    let deps = try AppDependencies.inMemory(llmService: MockLLMService(responses: []))
    let beforeScenario = deps.scenarioRepository as AnyObject
    let beforeSim = deps.simulationRepository as AnyObject
    let beforeTurn = deps.turnRepository as AnyObject
    let beforeBG = deps.backgroundManager
    let beforeGallery = deps.galleryService as AnyObject
    let beforeRegistry = deps.simulationActivityRegistry

    deps.regenerateLLMService(MockLLMService(responses: []))

    #expect(deps.scenarioRepository as AnyObject === beforeScenario)
    #expect(deps.simulationRepository as AnyObject === beforeSim)
    #expect(deps.turnRepository as AnyObject === beforeTurn)
    #expect(deps.backgroundManager === beforeBG)
    #expect(deps.galleryService as AnyObject === beforeGallery)
    #expect(
      deps.simulationActivityRegistry === beforeRegistry,
      "registry identity must be preserved — Settings UI observes it")
  }
}
