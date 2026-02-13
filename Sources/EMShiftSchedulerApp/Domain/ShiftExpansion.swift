import Foundation

enum ShiftExpansion {
    static func expand(project: ScheduleTemplateProject) -> [GeneratedShiftInstance] {
        guard let timezone = TimeZone(identifier: project.rules.timezone) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let start = calendar.startOfDay(for: project.blockWindow.startDate)
        let end = calendar.startOfDay(for: project.blockWindow.endDate)
        let orientationEnd = orientationEndDate(project: project, calendar: calendar, timezone: timezone)

        var instances: [GeneratedShiftInstance] = []
        var day = start

        while day <= end {
            let weekdayValue = calendar.component(.weekday, from: day)
            let weekday = Weekday(rawValue: weekdayValue)

            for template in project.shiftTemplates {
                guard let weekday, template.daysOffered.contains(weekday) else { continue }
                if template.isOvernight, isDayBeforeConferenceDay(weekday: weekday, conferenceDay: project.rules.conferenceDay) {
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
                if startDate < orientationEnd {
                    continue
                }
                if overlapsConferenceWindow(
                    startDate: startDate,
                    endDate: endDate,
                    calendar: calendar,
                    rules: project.rules,
                    timezone: timezone
                ) {
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

    private static func orientationEndDate(
        project: ScheduleTemplateProject,
        calendar: Calendar,
        timezone: TimeZone
    ) -> Date {
        let orientation = project.orientation
        let orientationDay = calendar.startOfDay(for: orientation.startDate)

        var startComponents = calendar.dateComponents([.year, .month, .day], from: orientationDay)
        startComponents.hour = orientation.startTime.hour
        startComponents.minute = orientation.startTime.minute
        startComponents.second = 0
        startComponents.timeZone = timezone

        var endComponents = calendar.dateComponents([.year, .month, .day], from: orientationDay)
        endComponents.hour = orientation.endTime.hour
        endComponents.minute = orientation.endTime.minute
        endComponents.second = 0
        endComponents.timeZone = timezone

        guard let startDate = calendar.date(from: startComponents),
              let rawEndDate = calendar.date(from: endComponents) else {
            return calendar.startOfDay(for: project.blockWindow.startDate)
        }

        if rawEndDate > startDate {
            return rawEndDate
        }
        return calendar.date(byAdding: .day, value: 1, to: rawEndDate) ?? rawEndDate
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

    private static func isDayBeforeConferenceDay(weekday: Weekday, conferenceDay: Weekday) -> Bool {
        let order: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let weekdayIndex = order.firstIndex(of: weekday),
              let conferenceIndex = order.firstIndex(of: conferenceDay) else {
            return false
        }
        return (weekdayIndex + 1) % order.count == conferenceIndex
    }

    private static func overlapsConferenceWindow(
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        rules: GlobalScheduleRules,
        timezone: TimeZone
    ) -> Bool {
        var day = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        while day <= endDay {
            if Weekday(rawValue: calendar.component(.weekday, from: day)) == rules.conferenceDay {
                var startComponents = calendar.dateComponents([.year, .month, .day], from: day)
                startComponents.hour = rules.conferenceStartTime.hour
                startComponents.minute = rules.conferenceStartTime.minute
                startComponents.second = 0
                startComponents.timeZone = timezone

                var endComponents = calendar.dateComponents([.year, .month, .day], from: day)
                endComponents.hour = rules.conferenceEndTime.hour
                endComponents.minute = rules.conferenceEndTime.minute
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

                if startDate < conferenceEnd && conferenceStart < endDate {
                    return true
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return false
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
