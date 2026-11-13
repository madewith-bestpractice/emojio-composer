import XCTest
@testable import flutter_midi_command_darwin

final class VirtualDeviceIdTests: XCTestCase {
    func testDestinationOnly() {
        let r = parseVirtualDeviceId("123")
        XCTAssertEqual(r.destination, 123)
        XCTAssertNil(r.source)
    }

    func testSourceAndDestination() {
        let r = parseVirtualDeviceId("123:456")
        XCTAssertEqual(r.destination, 123)
        XCTAssertEqual(r.source, 456)
    }

    // The 1.0.2 bug: ":456" was read as destination 456 and no source.
    func testSourceOnly() {
        let r = parseVirtualDeviceId(":456")
        XCTAssertNil(r.destination)
        XCTAssertEqual(r.source, 456)
    }
}
