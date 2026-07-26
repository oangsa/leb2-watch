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

}
