import AppKit
import XCTest

final class VoicePenIntegrationHostTests: XCTestCase {
    @MainActor
    func testHostedIntegrationTargetRunsInsideVoicePenApp() {
        XCTAssertNotNil(NSApp)
        XCTAssertEqual(Bundle.main.bundleURL.pathExtension, "app")
        XCTAssertTrue(Bundle.main.bundleIdentifier?.contains("VoicePen") == true)
    }
}
