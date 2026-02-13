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

    func testConferenceWindowBlocksOnlyOverlappingShifts() {
        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.rules.conferenceDay = .wednesday
        project.rules.conferenceStartTime = LocalTime(hour: 8, minute: 0)
        project.rules.conferenceEndTime = LocalTime(hour: 12, minute: 0)
        project.blockWindow.startDate = localDate(year: 2026, month: 2, day: 8, timezone: project.rules.timezone)
        project.blockWindow.endDate = localDate(year: 2026, month: 2, day: 14, timezone: project.rules.timezone)
        project.shiftTemplates = [
            ShiftTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
                name: "Conference Overlap",
                location: "A",
                isOvernight: false,
                minShifts: nil,
                maxShifts: nil,
                startTime: LocalTime(hour: 7, minute: 0),
                endTime: LocalTime(hour: 11, minute: 0),
                lengthHours: nil,
                daysOffered: [.wednesday],
                active: true
            ),
            ShiftTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
                name: "Conference Safe",
                location: "A",
                isOvernight: false,
                minShifts: nil,
                maxShifts: nil,
                startTime: LocalTime(hour: 13, minute: 0),
                endTime: LocalTime(hour: 17, minute: 0),
                lengthHours: nil,
                daysOffered: [.wednesday],
                active: true
            )
        ]

        let shifts = ShiftExpansion.expand(project: project)
        XCTAssertEqual(shifts.count, 1)
        XCTAssertEqual(shifts.first?.name, "Conference Safe")
        XCTAssertEqual(
            Calendar(identifier: .gregorian).component(.weekday, from: shifts[0].startDateTime),
            Weekday.wednesday.rawValue
        )
    }

    func testMetroJSONAllowsWednesdayOvernightsButNotTuesdayOvernights() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "/Users/roshanlodha/Documents/metroAIscheduler/metro.json"))
        let bundle = try JSONDecoder().decode(ShiftBundleTemplate.self, from: data)

        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.shiftTypes = bundle.shiftTypes ?? project.shiftTypes
        project.shiftTemplates = bundle.shifts
        project.rules.conferenceDay = .wednesday
        project.rules.conferenceStartTime = LocalTime(hour: 8, minute: 0)
        project.rules.conferenceEndTime = LocalTime(hour: 12, minute: 0)
        project.blockWindow.startDate = localDate(year: 2026, month: 2, day: 8, timezone: project.rules.timezone)
        project.blockWindow.endDate = localDate(year: 2026, month: 2, day: 14, timezone: project.rules.timezone)

        let shifts = ShiftExpansion.expand(project: project)
        let overnightTemplateIDs = Set(project.shiftTemplates.filter { $0.isOvernight }.map(\.id))
        let overnightShifts = shifts.filter { overnightTemplateIDs.contains($0.templateId) }
        XCTAssertFalse(overnightShifts.isEmpty)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: project.rules.timezone) ?? .current
        let weekdays = overnightShifts.map { calendar.component(.weekday, from: $0.startDateTime) }
        XCTAssertTrue(weekdays.contains(Weekday.wednesday.rawValue))
        XCTAssertFalse(weekdays.contains(Weekday.tuesday.rawValue))
    }

    func testOrientationBlocksShiftsUntilEndTime() {
        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.rules.timezone = "America/New_York"
        project.blockWindow.startDate = localDate(year: 2026, month: 2, day: 9, timezone: project.rules.timezone) // Monday
        project.blockWindow.endDate = localDate(year: 2026, month: 2, day: 10, timezone: project.rules.timezone)
        project.orientation.startDate = localDate(year: 2026, month: 2, day: 9, timezone: project.rules.timezone)
        project.orientation.startTime = LocalTime(hour: 8, minute: 0)
        project.orientation.endTime = LocalTime(hour: 12, minute: 0)
        project.rules.conferenceDay = .wednesday

        project.shiftTemplates = [
            ShiftTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
                name: "Morning Shift",
                location: "A",
                isOvernight: false,
                minShifts: nil,
                maxShifts: nil,
                startTime: LocalTime(hour: 7, minute: 0),
                endTime: LocalTime(hour: 15, minute: 0),
                lengthHours: nil,
                daysOffered: [.monday, .tuesday],
                active: true
            ),
            ShiftTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
                name: "Afternoon Shift",
                location: "B",
                isOvernight: false,
                minShifts: nil,
                maxShifts: nil,
                startTime: LocalTime(hour: 13, minute: 0),
                endTime: LocalTime(hour: 21, minute: 0),
                lengthHours: nil,
                daysOffered: [.monday, .tuesday],
                active: true
            )
        ]

        let shifts = ShiftExpansion.expand(project: project)
        let mondayShifts = shifts.filter {
            Calendar(identifier: .gregorian).component(.weekday, from: $0.startDateTime) == Weekday.monday.rawValue
        }

        XCTAssertEqual(mondayShifts.count, 1)
        XCTAssertEqual(mondayShifts.first?.name, "Afternoon Shift")
    }

    private func localDate(year: Int, month: Int, day: Int, timezone: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? Date()
    }
}
