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

            for template in project.shiftTemplates {
                guard let weekday, template.daysOffered.contains(weekday) else { continue }
                if template.isOvernight, isBeforeConferenceDay(weekday: weekday, conferenceDay: project.rules.conferenceDay) {
                    continue
                }

                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = template.startTime.hour
                components.minute = template.startTime.minute
                components.second = 0
                components.timeZone = timezone

                guard let startDate = calendar.date(from: components) else { continue }
                guard let endDate = resolveEndDate(startDate: startDate, template: template, calendar: calendar, rules: project.rules) else {
                    continue
                }
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
        return max(1, template.lengthHours ?? 10)
    }

    private static func resolveEndDate(
        startDate: Date,
        template: ShiftTemplate,
        calendar: Calendar,
        rules: GlobalScheduleRules
    ) -> Date? {
        if let endTime = template.endTime {
            var endComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
            endComponents.hour = endTime.hour
            endComponents.minute = endTime.minute
            endComponents.second = 0
            guard let sameDayEnd = calendar.date(from: endComponents) else { return nil }
            if sameDayEnd > startDate {
                return sameDayEnd
            }
            return calendar.date(byAdding: .day, value: 1, to: sameDayEnd)
        }

        let lengthHours = template.lengthHours ?? defaultLengthHours(template: template, rules: rules)
        guard lengthHours > 0 else { return nil }
        return calendar.date(byAdding: .hour, value: lengthHours, to: startDate)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func isBeforeConferenceDay(weekday: Weekday, conferenceDay: Weekday) -> Bool {
        let order: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let weekdayIndex = order.firstIndex(of: weekday),
              let conferenceIndex = order.firstIndex(of: conferenceDay) else {
            return false
        }
        return weekdayIndex < conferenceIndex
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
