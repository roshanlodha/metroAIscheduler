import Foundation

struct ValidationIssue: Identifiable, Equatable {
    var id = UUID()
    var field: String
    var message: String
}

enum ProjectValidator {
    static func validate(project: ScheduleTemplateProject) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if project.blockWindow.endDate < project.blockWindow.startDate {
            issues.append(.init(field: "blockWindow", message: "End date must be on or after start date."))
        }
        if project.rules.numShiftsRequired < 0 {
            issues.append(.init(field: "rules.numShiftsRequired", message: "Required shifts must be >= 0."))
        }
        if project.rules.timeOffHours < 0 {
            issues.append(.init(field: "rules.timeOffHours", message: "Time off hours must be >= 0."))
        }
        if project.shiftTemplates.isEmpty {
            issues.append(.init(field: "shiftTemplates", message: "Add at least one shift to the active template."))
        }
        if project.shiftTypes.isEmpty {
            issues.append(.init(field: "shiftTypes", message: "Define at least one shift type."))
        }
        if TimeZone(identifier: project.rules.timezone) == nil {
            issues.append(.init(field: "rules.timezone", message: "Timezone must be a valid IANA identifier."))
        }
        if project.rules.conferenceStartTime.hour == project.rules.conferenceEndTime.hour &&
            project.rules.conferenceStartTime.minute == project.rules.conferenceEndTime.minute {
            issues.append(.init(field: "rules.conferenceTime", message: "Conference start and end time cannot be equal."))
        }

        let typeIDs = Set(project.shiftTypes.map(\.id))
        for type in project.shiftTypes {
            if type.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "shiftType.\(type.id).name", message: "Shift type name is required."))
            }
            if let min = type.minShifts, let max = type.maxShifts, min > max {
                issues.append(.init(field: "shiftType.\(type.id).minMax", message: "Shift type \(type.name): min must be <= max."))
            }
        }

        for template in project.shiftTemplates {
            if let minShifts = template.minShifts, let maxShifts = template.maxShifts, minShifts > maxShifts {
                issues.append(.init(field: "template.\(template.id).minMax", message: "Template \(template.name): minShifts must be <= maxShifts."))
            }
            if template.daysOffered.isEmpty {
                issues.append(.init(field: "template.\(template.id).daysOffered", message: "Template \(template.name): select at least one weekday."))
            }
            if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "template.\(template.id).name", message: "Template name is required."))
            }
            if template.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "template.\(template.id).location", message: "Template location is required."))
            }
            if let typeID = template.shiftTypeId {
                if !typeIDs.contains(typeID) {
                    issues.append(.init(field: "template.\(template.id).shiftTypeId", message: "Template \(template.name): choose a valid shift type."))
                }
            } else {
                issues.append(.init(field: "template.\(template.id).shiftTypeId", message: "Template \(template.name): shift type is required."))
            }

            if let end = template.endTime {
                if end.hour < 0 || end.hour > 23 || end.minute < 0 || end.minute > 59 {
                    issues.append(.init(field: "template.\(template.id).endTime", message: "Template \(template.name): endTime is invalid."))
                }
            } else {
                if let hours = template.lengthHours {
                    if hours <= 0 {
                        issues.append(.init(field: "template.\(template.id).lengthHours", message: "Template \(template.name): lengthHours must be > 0."))
                    }
                } else {
                    if !template.isOvernight {
                        issues.append(.init(field: "template.\(template.id).timing", message: "Template \(template.name): set an end time."))
                    }
                    let defaultHours = ShiftExpansion.defaultLengthHours(template: template, rules: project.rules)
                    if defaultHours <= 0 {
                        issues.append(.init(field: "template.\(template.id).defaultLength", message: "Template \(template.name): default length must be > 0."))
                    }
                }
            }
        }

        return issues
    }
}
