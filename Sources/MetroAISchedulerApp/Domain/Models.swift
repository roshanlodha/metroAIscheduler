import Foundation

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

struct LocalTime: Codable, Hashable {
    var hour: Int
    var minute: Int

    init(hour: Int = 8, minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    var display: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct ShiftTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var location: String
    var isOvernight: Bool
    var minShifts: Int?
    var maxShifts: Int?
    var startTime: LocalTime
    var lengthHours: Int?
    var daysOffered: Set<Weekday>
    var active: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        location: String = "",
        isOvernight: Bool = false,
        minShifts: Int? = nil,
        maxShifts: Int? = nil,
        startTime: LocalTime = LocalTime(),
        lengthHours: Int? = 8,
        daysOffered: Set<Weekday> = Set(Weekday.allCases),
        active: Bool = true
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.isOvernight = isOvernight
        self.minShifts = minShifts
        self.maxShifts = maxShifts
        self.startTime = startTime
        self.lengthHours = lengthHours
        self.daysOffered = daysOffered
        self.active = active
    }
}

struct GlobalScheduleRules: Codable, Equatable {
    var timeOffHours: Int
    var numShiftsRequired: Int
    var timezone: String
    var noDoubleBooking: Bool
    var allowOvernightBeforeWednesday: Bool
    var solverTimeLimitSeconds: Int
    var overnightShiftWeight: Int

    static var `default`: GlobalScheduleRules {
        GlobalScheduleRules(
            timeOffHours: 10,
            numShiftsRequired: 4,
            timezone: "America/New_York",
            noDoubleBooking: true,
            allowOvernightBeforeWednesday: true,
            solverTimeLimitSeconds: 20,
            overnightShiftWeight: 1
        )
    }
}

struct Student: Identifiable, Codable, Equatable {
    var id: UUID
    var firstName: String
    var lastName: String
    var email: String

    init(id: UUID = UUID(), firstName: String = "", lastName: String = "", email: String = "") {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }

    var displayName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}

struct BlockWindow: Codable, Equatable {
    var startDate: Date
    var endDate: Date
}

struct GeneratedShiftInstance: Identifiable, Codable, Equatable {
    var id: String
    var templateId: UUID
    var startDateTime: Date
    var endDateTime: Date
    var isOvernight: Bool
    var location: String
    var name: String
}

struct Assignment: Codable, Equatable {
    var studentId: UUID
    var shiftInstanceId: String
}

struct ScheduleTemplateProject: Codable, Equatable {
    var schemaVersion: Int
    var name: String
    var shiftTemplates: [ShiftTemplate]
    var students: [Student]
    var rules: GlobalScheduleRules
    var blockWindow: BlockWindow

    static func sample(now: Date = Date()) -> ScheduleTemplateProject {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        return ScheduleTemplateProject(
            schemaVersion: 1,
            name: "Sample Metro Project",
            shiftTemplates: [
                ShiftTemplate(name: "Morning Dispatch", location: "Central", isOvernight: false, minShifts: 0, maxShifts: 3, startTime: LocalTime(hour: 8, minute: 0), lengthHours: 8, daysOffered: [.monday, .tuesday, .wednesday, .thursday, .friday], active: true),
                ShiftTemplate(name: "Overnight Ops", location: "North Yard", isOvernight: true, minShifts: 0, maxShifts: 2, startTime: LocalTime(hour: 20, minute: 0), lengthHours: 12, daysOffered: [.wednesday, .thursday, .friday, .saturday], active: true)
            ],
            students: [
                Student(firstName: "Alex", lastName: "Kim", email: "alex@example.edu"),
                Student(firstName: "Jordan", lastName: "Patel", email: "jordan@example.edu")
            ],
            rules: .default,
            blockWindow: BlockWindow(startDate: start, endDate: end)
        )
    }
}

struct ScheduleResult: Codable, Equatable {
    var generatedAt: Date
    var shiftInstances: [GeneratedShiftInstance]
    var assignments: [Assignment]
}

struct SolverDiagnostic: Codable, Equatable {
    var message: String
    var details: [String]
}
