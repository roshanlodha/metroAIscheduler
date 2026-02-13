import XCTest
@testable import EMShiftSchedulerApp

final class JSONCodingTests: XCTestCase {
    func testProjectRoundTrip() throws {
        let project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScheduleTemplateProject.self, from: data)

        XCTAssertEqual(project.schemaVersion, decoded.schemaVersion)
        XCTAssertEqual(project.shiftTemplates.count, decoded.shiftTemplates.count)
        XCTAssertEqual(project.students.count, decoded.students.count)
    }
}
