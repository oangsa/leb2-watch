import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testBackgroundRefreshStatusNames() {
    XCTAssertEqual(
      BackgroundRefreshStatusBridge.refreshStatusName(for: .available),
      "available"
    )
    XCTAssertEqual(
      BackgroundRefreshStatusBridge.refreshStatusName(for: .denied),
      "denied"
    )
    XCTAssertEqual(
      BackgroundRefreshStatusBridge.refreshStatusName(for: .restricted),
      "restricted"
    )
  }

  func testBackgroundExpirationGenerationsAreDistinct() {
    let coordinator = BackgroundRefreshExpirationCoordinator()

    XCTAssertNotEqual(coordinator.begin(), coordinator.begin())
  }

  func testExpirationBeforeAttachIsLatched() {
    let coordinator = BackgroundRefreshExpirationCoordinator()
    let generation = coordinator.begin(generation: "generation-a")
    XCTAssertTrue(coordinator.expire(generation: generation))
    let notifier = RecordingExpirationNotifier()

    let snapshot = coordinator.attach(notifier: notifier)

    XCTAssertEqual(snapshot?.generation, generation)
    XCTAssertEqual(snapshot?.expired, true)
    XCTAssertEqual(notifier.generations, [])
  }

  func testLiveExpirationNotifiesMatchingGenerationOnlyOnce() {
    let coordinator = BackgroundRefreshExpirationCoordinator()
    let generation = coordinator.begin(generation: "generation-a")
    let notifier = RecordingExpirationNotifier()
    _ = coordinator.attach(notifier: notifier)

    XCTAssertTrue(coordinator.expire(generation: generation))
    XCTAssertFalse(coordinator.expire(generation: generation))

    XCTAssertEqual(notifier.generations, [generation])
  }

  func testStaleExpirationCannotNotifyNewGeneration() {
    let coordinator = BackgroundRefreshExpirationCoordinator()
    let oldGeneration = coordinator.begin(generation: "generation-a")
    let currentGeneration = coordinator.begin(generation: "generation-b")
    let notifier = RecordingExpirationNotifier()
    _ = coordinator.attach(notifier: notifier)

    XCTAssertFalse(coordinator.expire(generation: oldGeneration))
    XCTAssertTrue(coordinator.expire(generation: currentGeneration))

    XCTAssertEqual(notifier.generations, [currentGeneration])
  }

  func testStaleOrMalformedDetachCannotClearNewGeneration() {
    let coordinator = BackgroundRefreshExpirationCoordinator()
    let oldGeneration = coordinator.begin(generation: "generation-a")
    let currentGeneration = coordinator.begin(generation: "generation-b")
    let notifier = RecordingExpirationNotifier()
    _ = coordinator.attach(notifier: notifier)

    XCTAssertFalse(coordinator.detach(generation: oldGeneration))
    XCTAssertFalse(coordinator.detach(generation: "malformed"))
    XCTAssertTrue(coordinator.expire(generation: currentGeneration))

    XCTAssertEqual(notifier.generations, [currentGeneration])
  }

  func testExpirationChainInvokesOriginalHandlerOnce() {
    let coordinator = BackgroundRefreshExpirationCoordinator()
    let generation = coordinator.begin(generation: "generation-a")
    var originalCalls = 0
    let chain = BackgroundRefreshExpirationChain(
      coordinator: coordinator,
      generation: generation,
      original: { originalCalls += 1 }
    )

    chain.invoke()
    chain.invoke()

    XCTAssertEqual(originalCalls, 1)
  }
}

private final class RecordingExpirationNotifier:
  BackgroundRefreshExpirationNotifier
{
  var generations: [String] = []

  func notifyExpired(generation: String) {
    generations.append(generation)
  }
}
