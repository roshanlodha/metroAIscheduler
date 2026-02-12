import XCTest
@testable import MetroAISchedulerApp

final class SolverFixtureTests: XCTestCase {
    func testDeterministicFixtureSolverProducesStableAssignments() throws {
        var project = ScheduleTemplateProject.sample(now: Date(timeIntervalSince1970: 1_700_000_000))
        project.rules.numShiftsRequired = 1
        project.rules.timeOffHours = 0
        project.rules.noDoubleBooking = true

        let shifts = ShiftExpansion.expand(project: project)
        let solver = DeterministicFixtureSolver()
        let result = try solver.solve(project: project, shiftInstances: shifts)

        XCTAssertEqual(result.assignments.count, project.students.count)
        let ids = result.assignments.map(\.shiftInstanceId)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
