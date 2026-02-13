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

        let overnightCount = overnightShiftsRequired(project: project)
        let assignmentTarget = max(0, project.rules.numShiftsRequired - max(0, overnightCount - 1))

        for student in sortedStudents {
            var assigned = 0
            for shift in sortedShifts {
                if project.rules.noDoubleBooking && shiftTaken.contains(shift.id) { continue }
                if overlapsConference(shift: shift, project: project) { continue }
                if isOvernightBeforeConference(shift: shift, project: project) { continue }
                let existing = usedByStudent[student.id, default: []]
                let conflict = existing.contains { ShiftConflictDetector.violatesRest($0, shift, minimumHours: project.rules.timeOffHours) }
                if conflict { continue }
                assignments.append(Assignment(studentId: student.id, shiftInstanceId: shift.id))
                usedByStudent[student.id, default: []].append(shift)
                shiftTaken.insert(shift.id)
                assigned += 1
                if assigned >= assignmentTarget { break }
            }
        }

        return ScheduleResult(generatedAt: Date(), shiftInstances: shiftInstances, assignments: assignments)
    }

    private func overnightShiftsRequired(project: ScheduleTemplateProject) -> Int {
        guard let overnightType = project.shiftTypes.first(where: { $0.name.caseInsensitiveCompare("Overnight") == .orderedSame }) else {
            return 0
        }
        return max(0, overnightType.minShifts ?? 0)
    }

    private func overlapsConference(shift: GeneratedShiftInstance, project: ScheduleTemplateProject) -> Bool {
        guard let timezone = TimeZone(identifier: project.rules.timezone) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var day = calendar.startOfDay(for: shift.startDateTime)
        let endDay = calendar.startOfDay(for: shift.endDateTime)

        while day <= endDay {
            if Weekday(rawValue: calendar.component(.weekday, from: day)) == project.rules.conferenceDay {
                var startComponents = calendar.dateComponents([.year, .month, .day], from: day)
                startComponents.hour = project.rules.conferenceStartTime.hour
                startComponents.minute = project.rules.conferenceStartTime.minute
                startComponents.second = 0
                startComponents.timeZone = timezone

                var endComponents = calendar.dateComponents([.year, .month, .day], from: day)
                endComponents.hour = project.rules.conferenceEndTime.hour
                endComponents.minute = project.rules.conferenceEndTime.minute
                endComponents.second = 0
                endComponents.timeZone = timezone

                guard let conferenceStart = calendar.date(from: startComponents),
                      let rawConferenceEnd = calendar.date(from: endComponents) else {
                    return false
                }

                let conferenceEnd: Date
                if rawConferenceEnd > conferenceStart {
                    conferenceEnd = rawConferenceEnd
                } else {
                    conferenceEnd = calendar.date(byAdding: .day, value: 1, to: rawConferenceEnd) ?? rawConferenceEnd
                }

                if shift.startDateTime < conferenceEnd && conferenceStart < shift.endDateTime {
                    return true
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return false
    }

    private func isOvernightBeforeConference(shift: GeneratedShiftInstance, project: ScheduleTemplateProject) -> Bool {
        guard shift.isOvernight else { return false }
        guard let timezone = TimeZone(identifier: project.rules.timezone) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let startWeekday = Weekday(rawValue: calendar.component(.weekday, from: shift.startDateTime))
        guard let startWeekday else { return false }

        let order: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let weekdayIndex = order.firstIndex(of: startWeekday),
              let conferenceIndex = order.firstIndex(of: project.rules.conferenceDay) else {
            return false
        }
        return (weekdayIndex + 1) % order.count == conferenceIndex
    }
}
