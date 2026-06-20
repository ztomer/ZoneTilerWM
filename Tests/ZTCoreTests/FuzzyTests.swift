import XCTest
@testable import ZTCore

final class FuzzyTests: XCTestCase {
    func testEmptyNeedleMatchesAnything() {
        XCTAssertTrue(Fuzzy.matches("", in: "Safari"))
        XCTAssertTrue(Fuzzy.matches("", in: ""))
    }

    func testSubstringMatches() {
        XCTAssertTrue(Fuzzy.matches("saf", in: "Safari"))
        XCTAssertTrue(Fuzzy.matches("fari", in: "Safari"))
        XCTAssertTrue(Fuzzy.matches("Safari", in: "Safari"))
    }

    func testSubsequenceMatches() {
        XCTAssertTrue(Fuzzy.matches("sf", in: "Safari"))      // s…f
        XCTAssertTrue(Fuzzy.matches("sfri", in: "Safari"))
        XCTAssertTrue(Fuzzy.matches("trml", in: "Terminal"))
    }

    func testOrderMatters() {
        XCTAssertFalse(Fuzzy.matches("fs", in: "Safari"))     // f before s → no
        XCTAssertFalse(Fuzzy.matches("ras", in: "Safari"))
    }

    func testNonMatch() {
        XCTAssertFalse(Fuzzy.matches("xyz", in: "Safari"))
        XCTAssertFalse(Fuzzy.matches("chrome", in: "Safari"))
        XCTAssertFalse(Fuzzy.matches("safarii", in: "Safari"))  // needle longer / extra char
    }

    func testCaseInsensitive() {
        XCTAssertTrue(Fuzzy.matches("SAFARI", in: "safari"))
        XCTAssertTrue(Fuzzy.matches("sAf", in: "SaFaRi"))
    }

    func testEmptyHayOnlyMatchesEmptyNeedle() {
        XCTAssertTrue(Fuzzy.matches("", in: ""))
        XCTAssertFalse(Fuzzy.matches("a", in: ""))
    }

    func testSuffixAndFullMatchAtEndIndex() {
        // Guards the "found at endIndex → index(after:) → empty slice" path stays safe (no crash).
        XCTAssertTrue(Fuzzy.matches("b", in: "ab"))
        XCTAssertTrue(Fuzzy.matches("ab", in: "ab"))
        XCTAssertFalse(Fuzzy.matches("abc", in: "ab"))
    }

    func testDuplicateCharsConsumeLeftToRight() {
        XCTAssertTrue(Fuzzy.matches("aa", in: "banana"))      // two a's exist
        XCTAssertFalse(Fuzzy.matches("aaaa", in: "banana"))   // only three a's
        XCTAssertTrue(Fuzzy.matches("aaa", in: "banana"))
    }
}
