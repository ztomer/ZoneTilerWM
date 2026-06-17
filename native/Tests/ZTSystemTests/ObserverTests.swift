// ObserverTests — read-only system observers (screens / audio). Machine-dependent, so each
// test skips when the relevant hardware is absent (e.g. headless CI).

import XCTest
@testable import ZTCore
@testable import ZTSystem

final class ObserverTests: XCTestCase {

    func testScreensHaveStableUUIDsAndSaneFrames() throws {
        let provider = NSScreenProvider()
        let screens = provider.allScreens()
        try XCTSkipUnless(!screens.isEmpty, "no displays on this machine")

        for s in screens {
            XCTAssertFalse(s.uuid.isEmpty, "screen UUID should be non-empty")
            XCTAssertGreaterThan(s.fullFrame.w, 0)
            XCTAssertGreaterThan(s.fullFrame.h, 0)
            // Visible frame is within the full frame.
            XCTAssertGreaterThanOrEqual(s.frame.x, s.fullFrame.x)
            XCTAssertGreaterThanOrEqual(s.frame.y, s.fullFrame.y)
            XCTAssertLessThanOrEqual(s.frame.w, s.fullFrame.w)
            XCTAssertLessThanOrEqual(s.frame.h, s.fullFrame.h)
        }
        XCTAssertNotNil(provider.mainScreen())
        // Stable lookup by UUID.
        let first = screens[0]
        XCTAssertEqual(provider.screen(uuid: first.uuid), first)
    }

    func testScreenContainingPoint() throws {
        let provider = NSScreenProvider()
        guard let main = provider.mainScreen() else { throw XCTSkip("no main screen") }
        let center = (x: main.fullFrame.x + main.fullFrame.w / 2, y: main.fullFrame.y + main.fullFrame.h / 2)
        XCTAssertEqual(provider.screen(containing: center)?.uuid, main.uuid)
    }

    func testAudioOutputDevicesEnumerate() throws {
        let devices = AudioDevices.outputDevices()
        try XCTSkipUnless(!devices.isEmpty, "no audio output devices on this machine")
        for d in devices {
            XCTAssertFalse(d.name.isEmpty)
            XCTAssertFalse(d.uid.isEmpty)
        }
        // Default (if any) should be one of the enumerated devices.
        if let def = AudioDevices.defaultOutputName() {
            XCTAssertTrue(devices.contains { $0.name == def })
        }
    }
}
