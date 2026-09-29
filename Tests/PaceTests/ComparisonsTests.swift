import XCTest
@testable import Pace

final class ComparisonsTests: XCTestCase {
    func testRotationWraps() {
        let a = Comparisons.sentence(tokens: 18_000_000, index: 0)
        let b = Comparisons.sentence(tokens: 18_000_000, index: 4)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, Comparisons.sentence(tokens: 18_000_000, index: 1))
        XCTAssertEqual(Comparisons.sentence(tokens: 18_000_000, index: -1), Comparisons.sentence(tokens: 18_000_000, index: 3))
    }

    func testMathMatchesPrototype() {
        // 18M tokens -> 13.5M words -> meters = 13.5M/8*24/160*0.0254 = 6429.4 m -> 6.4 km
        XCTAssertEqual(Comparisons.sentence(tokens: 18_000_000, index: 0), "On a phone, that's about 6.4 km of doomscrolling.")
        XCTAssertEqual(Comparisons.sentence(tokens: 18_000_000, index: 1), "Stacked up, that feed would be 19 Eiffel Towers tall.")
        XCTAssertEqual(Comparisons.sentence(tokens: 18_000_000, index: 2), "Doomscrolled at reading speed, that's 38 days without putting the phone down.")
        XCTAssertEqual(Comparisons.sentence(tokens: 18_000_000, index: 3), "That's roughly 540 thousand tweets' worth of scrolling.")
    }

    func testSmallNumbers() {
        XCTAssertEqual(Comparisons.sentence(tokens: 1_500_000, index: 0), "On a phone, that's about 536 m of doomscrolling.")
        XCTAssertEqual(Comparisons.round1(1.66), "1.7")
        XCTAssertEqual(Comparisons.round1(12.6), "13")
        XCTAssertEqual(Comparisons.round1(3.0), "3")
    }
}
