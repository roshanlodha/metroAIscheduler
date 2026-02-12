import Foundation

enum CSVExporter {
    static func export(project: ScheduleTemplateProject, result: ScheduleResult) -> String {
        let studentMap = Dictionary(uniqueKeysWithValues: project.students.map { ($0.id, $0.displayName) })
        let shiftMap = Dictionary(uniqueKeysWithValues: result.shiftInstances.map { ($0.id, $0) })

        var rows: [String] = ["student,shift_name,location,start,end,overnight"]
        let formatter = ISO8601DateFormatter()

        for assignment in result.assignments {
            guard let shift = shiftMap[assignment.shiftInstanceId] else { continue }
            let student = studentMap[assignment.studentId] ?? assignment.studentId.uuidString
            rows.append([
                quoted(student),
                quoted(shift.name),
                quoted(shift.location),
                quoted(formatter.string(from: shift.startDateTime)),
                quoted(formatter.string(from: shift.endDateTime)),
                shift.isOvernight ? "true" : "false"
            ].joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

enum ICSExporter {
    static func export(for student: Student, project: ScheduleTemplateProject, result: ScheduleResult) -> String {
        let assignments = result.assignments.filter { $0.studentId == student.id }
        let shiftMap = Dictionary(uniqueKeysWithValues: result.shiftInstances.map { ($0.id, $0) })
        let tz = project.rules.timezone

        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//EM Shift Scheduler//EN",
            "CALSCALE:GREGORIAN"
        ]

        for assignment in assignments {
            guard let shift = shiftMap[assignment.shiftInstanceId] else { continue }
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(assignment.shiftInstanceId)-\(student.id.uuidString)")
            lines.append("DTSTAMP:\(utcICSDate(Date()))")
            lines.append("DTSTART;TZID=\(tz):\(localICSDate(shift.startDateTime, timezone: tz))")
            lines.append("DTEND;TZID=\(tz):\(localICSDate(shift.endDateTime, timezone: tz))")
            lines.append("SUMMARY:\(escapeICS(shift.name))")
            lines.append("LOCATION:\(escapeICS(shift.location))")
            lines.append("DESCRIPTION:Assigned by EM Shift Scheduler")
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    private static func utcICSDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func localICSDate(_ date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func escapeICS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
