import XCTest
@testable import MetroAISchedulerApp

final class ConflictDetectionTests: XCTestCase {
    func testOverlapAndRestConflict() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shiftA = GeneratedShiftInstance(
            id: "a",
            templateId: UUID(),
            startDateTime: now,
            endDateTime: now.addingTimeInterval(4 * 3600),
            isOvernight: false,
            location: "X",
            name: "A"
        )
        let shiftB = GeneratedShiftInstance(
            id: "b",
            templateId: UUID(),
            startDateTime: now.addingTimeInterval(3 * 3600),
            endDateTime: now.addingTimeInterval(7 * 3600),
            isOvernight: false,
            location: "X",
            name: "B"
        )
        let shiftC = GeneratedShiftInstance(
            id: "c",
            templateId: UUID(),
            startDateTime: now.addingTimeInterval(5 * 3600),
            endDateTime: now.addingTimeInterval(8 * 3600),
            isOvernight: false,
            location: "X",
            name: "C"
        )

        XCTAssertTrue(ShiftConflictDetector.intervalsOverlap(shiftA, shiftB))
        XCTAssertTrue(ShiftConflictDetector.violatesRest(shiftA, shiftC, minimumHours: 2))
        XCTAssertFalse(ShiftConflictDetector.violatesRest(shiftA, shiftC, minimumHours: 1))
    }
}
