import Foundation

enum SolverError: Error, LocalizedError {
    case invalidInput(String)
    case executionFailed(String)
    case infeasible(SolverDiagnostic)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .executionFailed(let message):
            return message
        case .infeasible(let diagnostic):
            return ([diagnostic.message] + diagnostic.details).joined(separator: "\n")
        }
    }
}

protocol SolverAdapter {
    func solve(project: ScheduleTemplateProject, shiftInstances: [GeneratedShiftInstance]) throws -> ScheduleResult
}

struct PythonSolverInput: Codable {
    var project: ScheduleTemplateProject
    var shiftInstances: [GeneratedShiftInstance]
}

struct PythonSolverOutput: Codable {
    var status: String
    var assignments: [Assignment]
    var diagnostic: SolverDiagnostic?
}

struct DeterministicFixtureSolver: SolverAdapter {
    func solve(project: ScheduleTemplateProject, shiftInstances: [GeneratedShiftInstance]) throws -> ScheduleResult {
        let sortedStudents = project.students.sorted { $0.id.uuidString < $1.id.uuidString }
        let sortedShifts = shiftInstances.sorted { $0.id < $1.id }

        var assignments: [Assignment] = []
        var usedByStudent: [UUID: [GeneratedShiftInstance]] = [:]
        var shiftTaken: Set<String> = []

        let assignmentTarget = max(0, project.rules.numShiftsRequired - project.rules.overnightBlockCount + 1)

        for student in sortedStudents {
            var score = 0
            for shift in sortedShifts {
                if project.rules.noDoubleBooking && shiftTaken.contains(shift.id) { continue }
                let existing = usedByStudent[student.id, default: []]
                let conflict = existing.contains { ShiftConflictDetector.violatesRest($0, shift, minimumHours: project.rules.timeOffHours) }
                if conflict { continue }
                assignments.append(Assignment(studentId: student.id, shiftInstanceId: shift.id))
                usedByStudent[student.id, default: []].append(shift)
                shiftTaken.insert(shift.id)
                score += shift.isOvernight ? project.rules.overnightShiftWeight : 1
                if score >= assignmentTarget { break }
            }
        }

        return ScheduleResult(generatedAt: Date(), shiftInstances: shiftInstances, assignments: assignments)
    }
}
