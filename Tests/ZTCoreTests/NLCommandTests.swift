// NLCommandTests — pure prompt-building + structured-command → ActionRequest mapping.

import XCTest
@testable import ZTCore

final class NLCommandTests: XCTestCase {

    func testSystemPromptListsCatalogActions() {
        let prompt = NLCommand.systemPrompt(catalog: ActionParser.catalog)
        XCTAssertTrue(prompt.contains("tile"))
        XCTAssertTrue(prompt.contains("autotile"))
        XCTAssertTrue(prompt.contains("focus-screen"))
        // params + allowed values surface so the model emits valid commands
        XCTAssertTrue(prompt.contains("zone"))
        XCTAssertTrue(prompt.contains("next/previous"))
    }

    func testMapsValidStructuredCommands() {
        let out = NLCommand.requests(from: [
            (action: "tile", params: ["zone": "h"]),
            (action: "autotile", params: [:]),
            (action: "focus-screen", params: ["direction": "next"]),
        ])
        XCTAssertEqual(out, [.tileFocusedToZone(zone: "h"), .autoTileScreen, .focusScreen(direction: .next)])
    }

    func testDropsInvalidCommands() {
        let out = NLCommand.requests(from: [
            (action: "tile", params: ["zone": "h"]),    // valid
            (action: "bogus", params: [:]),             // unknown → dropped
            (action: "tile", params: [:]),              // missing zone → dropped
            (action: "focus-screen", params: ["direction": "sideways"]),  // bad direction → dropped
        ])
        XCTAssertEqual(out, [.tileFocusedToZone(zone: "h")])
    }
}
