import Foundation

enum ShiftExpansion {
    static func expand(project: ScheduleTemplateProject) -> [GeneratedShiftInstance] {
        guard let timezone = TimeZone(identifier: project.rules.timezone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let start = calendar.startOfDay(for: project.blockWindow.startDate)
        let end = calendar.startOfDay(for: project.blockWindow.endDate)

        var instances: [GeneratedShiftInstance] = []
        var day = start

        while day <= end {
            let weekdayValue = calendar.component(.weekday, from: day)
            let weekday = Weekday(rawValue: weekdayValue)

            for template in project.shiftTemplates where template.active {
                guard let weekday, template.daysOffered.contains(weekday) else { continue }
                if template.isOvernight, !project.rules.allowOvernightBeforeWednesday,
                   weekday == .monday || weekday == .tuesday {
                    continue
                }

                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = template.startTime.hour
                components.minute = template.startTime.minute
                components.second = 0
                components.timeZone = timezone

                guard let startDate = calendar.date(from: components) else { continue }
                let lengthHours = template.lengthHours ?? defaultLengthHours(template: template, rules: project.rules)
                guard lengthHours > 0 else { continue }

                guard let endDate = calendar.date(byAdding: .hour, value: lengthHours, to: startDate) else { continue }
                let overnight = template.isOvernight || !calendar.isDate(startDate, inSameDayAs: endDate)

                let identifier = "\(template.id.uuidString.lowercased())|\(isoString(startDate))"
                instances.append(
                    GeneratedShiftInstance(
                        id: identifier,
                        templateId: template.id,
                        startDateTime: startDate,
                        endDateTime: endDate,
                        isOvernight: overnight,
                        location: template.location,
                        name: template.name
                    )
                )
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return instances.sorted { $0.startDateTime < $1.startDateTime }
    }

    static func defaultLengthHours(template: ShiftTemplate, rules: GlobalScheduleRules) -> Int {
        guard template.isOvernight else { return template.lengthHours ?? 0 }
        return max(1, (rules.numShiftsRequired * 24) - rules.timeOffHours)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct ShiftConflictDetector {
    static func intervalsOverlap(_ a: GeneratedShiftInstance, _ b: GeneratedShiftInstance) -> Bool {
        a.startDateTime < b.endDateTime && b.startDateTime < a.endDateTime
    }

    static func violatesRest(_ a: GeneratedShiftInstance, _ b: GeneratedShiftInstance, minimumHours: Int) -> Bool {
        if intervalsOverlap(a, b) { return true }
        let rest = TimeInterval(max(0, minimumHours) * 3600)

        if a.endDateTime <= b.startDateTime {
            return b.startDateTime.timeIntervalSince(a.endDateTime) < rest
        }
        if b.endDateTime <= a.startDateTime {
            return a.startDateTime.timeIntervalSince(b.endDateTime) < rest
        }
        return true
    }
}
