import XCTest
@testable import KehaiCore

final class PartnerSelectionTests: XCTestCase {
    private let all = ["a", "b", "c", "d", "e", "f"]

    func testNothingSelectedUsesConnectionOrder() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: [], limit: 4), ["a", "b", "c", "d"])
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: [], limit: 1), ["a"])
    }

    func testSelectedOrderIsKept() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: ["e", "b"], limit: 4), ["e", "b"])
    }

    func testSelectionIsCutToLimit() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: ["f", "e", "d"], limit: 1), ["f"])
        XCTAssertEqual(
            PartnerSelection.resolve(available: all, selected: ["a", "b", "c", "d", "e"], limit: 4),
            ["a", "b", "c", "d"]
        )
    }

    func testRemovedPartnersAreDropped() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: ["x", "c"], limit: 4), ["c"])
    }

    func testAllSelectedRemovedFallsBackToAuto() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: ["x", "y"], limit: 2), ["a", "b"])
    }

    func testDuplicatesAreIgnored() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: ["b", "b", "c"], limit: 4), ["b", "c"])
    }

    func testNoPartnersAvailable() {
        XCTAssertEqual(PartnerSelection.resolve(available: [String](), selected: ["a"], limit: 4), [])
    }

    func testZeroLimit() {
        XCTAssertEqual(PartnerSelection.resolve(available: all, selected: [], limit: 0), [])
    }
}
