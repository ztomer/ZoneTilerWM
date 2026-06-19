// AppSwitcherTests — mirrors tests/repro_ambiguous_apps.lua plus special-mapping and
// hide-workaround cases.

import XCTest
@testable import ZTCore

final class AppSwitcherTests: XCTestCase {

    private let notionCfg = AppSwitcher.Config(
        ambiguousApps: [["notion", "notion calendar"], ["notion", "notion mail"]])

    func testFrontNotionToggleCalendarLaunches() {
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Notion", target: "Notion Calendar", config: notionCfg),
                       .launchOrFocus(app: "Notion Calendar"))
    }

    func testFrontCalendarToggleNotionLaunches() {
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Notion Calendar", target: "Notion", config: notionCfg),
                       .launchOrFocus(app: "Notion"))
    }

    func testFrontCalendarToggleCalendarHides() {
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Notion Calendar", target: "Notion Calendar", config: notionCfg),
                       .hide)
    }

    func testTrailingSpaceFrontStillAmbiguous() {
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Notion ", target: "Notion Calendar", config: notionCfg),
                       .launchOrFocus(app: "Notion Calendar"))
    }

    func testSubstringMatchHidesWhenNotAmbiguous() {
        // No ambiguity configured: "Code" front, toggle "Code" -> same -> hide.
        let cfg = AppSwitcher.Config()
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Code", target: "Code", config: cfg), .hide)
        // Substring: front "Visual Studio Code", target "Code" -> contains -> hide.
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Visual Studio Code", target: "Code", config: cfg), .hide)
    }

    func testSpecialMappingMatchesLaunchVsDisplayName() {
        // launch name "BambuStudio" maps to display name "Bambu Studio".
        let cfg = AppSwitcher.Config(specialMappings: ["bambustudio": "bambu studio"])
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Bambu Studio", target: "BambuStudio", config: cfg), .hide)
    }

    func testHideWorkaroundUsesMenuItem() {
        let cfg = AppSwitcher.Config(hideWorkaroundApps: ["Arc"])
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Arc", target: "Arc", config: cfg),
                       .hideViaMenu(menuItem: "Hide Arc"))
    }

    func testDifferentAppLaunches() {
        XCTAssertEqual(AppSwitcher.decide(frontApp: "Safari", target: "Mail", config: AppSwitcher.Config()),
                       .launchOrFocus(app: "Mail"))
    }
}
