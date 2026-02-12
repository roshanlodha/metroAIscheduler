import XCTest
@testable import MetroAISchedulerApp

final class ShiftExpansionTests: XCTestCase {
    func testExpansionRespectsWeekdaysAndDeterministicID() {
        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.shiftTemplates = [
            ShiftTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Mon Only",
                location: "A",
                isOvernight: false,
                minShifts: nil,
                maxShifts: nil,
                startTime: LocalTime(hour: 9, minute: 0),
                lengthHours: 8,
                daysOffered: [.monday],
                active: true
            )
        ]
        let shifts = ShiftExpansion.expand(project: project)
        XCTAssertFalse(shifts.isEmpty)
        XCTAssertTrue(shifts.allSatisfy { Calendar(identifier: .gregorian).component(.weekday, from: $0.startDateTime) == Weekday.monday.rawValue })
        XCTAssertTrue(shifts[0].id.contains("00000000-0000-0000-0000-000000000001"))
    }
}
