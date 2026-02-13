import XCTest
@testable import EMShiftSchedulerApp

final class ICSExporterTests: XCTestCase {
    func testICSIncludesConferenceEvents() {
        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.rules.timezone = "America/New_York"
        project.rules.conferenceDay = .wednesday
        project.rules.conferenceStartTime = LocalTime(hour: 8, minute: 0)
        project.rules.conferenceEndTime = LocalTime(hour: 12, minute: 0)
        project.blockWindow.startDate = localDate(year: 2026, month: 2, day: 9, timezone: project.rules.timezone)
        project.blockWindow.endDate = localDate(year: 2026, month: 2, day: 22, timezone: project.rules.timezone)

        let student = Student(firstName: "Taylor", lastName: "Lee", email: "taylor@example.edu")
        project.students = [student]
        let result = ScheduleResult(generatedAt: Date(), shiftInstances: [], assignments: [])

        let ics = ICSExporter.export(for: student, project: project, result: result)

        XCTAssertTrue(ics.contains("SUMMARY:Conference"))
        XCTAssertTrue(ics.contains("LOCATION:Conference"))
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
