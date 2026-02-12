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

struct ShiftBundleTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shifts: [ShiftTemplate]

    init(id: UUID = UUID(), name: String, shifts: [ShiftTemplate]) {
        self.id = id
        self.name = name
        self.shifts = shifts
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
    var templateLibrary: [ShiftBundleTemplate]
    var students: [Student]
    var rules: GlobalScheduleRules
    var blockWindow: BlockWindow

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case shiftTemplates
        case templateLibrary
        case students
        case rules
        case blockWindow
    }

    init(
        schemaVersion: Int,
        name: String,
        shiftTemplates: [ShiftTemplate],
        templateLibrary: [ShiftBundleTemplate],
        students: [Student],
        rules: GlobalScheduleRules,
        blockWindow: BlockWindow
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.shiftTemplates = shiftTemplates
        self.templateLibrary = templateLibrary
        self.students = students
        self.rules = rules
        self.blockWindow = blockWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        shiftTemplates = try container.decodeIfPresent([ShiftTemplate].self, forKey: .shiftTemplates) ?? []
        templateLibrary = try container.decodeIfPresent([ShiftBundleTemplate].self, forKey: .templateLibrary) ?? []
        students = try container.decodeIfPresent([Student].self, forKey: .students) ?? []
        rules = try container.decodeIfPresent(GlobalScheduleRules.self, forKey: .rules) ?? .default
        blockWindow = try container.decode(BlockWindow.self, forKey: .blockWindow)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        try container.encode(shiftTemplates, forKey: .shiftTemplates)
        try container.encode(templateLibrary, forKey: .templateLibrary)
        try container.encode(students, forKey: .students)
        try container.encode(rules, forKey: .rules)
        try container.encode(blockWindow, forKey: .blockWindow)
    }

    static func empty(now: Date = Date()) -> ScheduleTemplateProject {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        return ScheduleTemplateProject(
            schemaVersion: 2,
            name: "Untitled Project",
            shiftTemplates: [],
            templateLibrary: [MetroPresetFactory.metroEDTemplate()],
            students: [],
            rules: .default,
            blockWindow: BlockWindow(startDate: start, endDate: end)
        )
    }

    static func sample(now: Date = Date()) -> ScheduleTemplateProject {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 13, to: start) ?? start
        let metroTemplate = MetroPresetFactory.metroEDTemplate()
        return ScheduleTemplateProject(
            schemaVersion: 2,
            name: "Sample Metro Project",
            shiftTemplates: metroTemplate.shifts,
            templateLibrary: [metroTemplate],
            students: [
                Student(firstName: "Alex", lastName: "Kim", email: "alex@example.edu"),
                Student(firstName: "Jordan", lastName: "Patel", email: "jordan@example.edu")
            ],
            rules: .default,
            blockWindow: BlockWindow(startDate: start, endDate: end)
        )
    }
}

enum MetroPresetFactory {
    static func metroEDTemplate() -> ShiftBundleTemplate {
        let regularDays: Set<Weekday> = [.monday, .tuesday, .thursday, .friday, .saturday, .sunday]
        let overnightDays: Set<Weekday> = [.monday, .thursday, .friday, .saturday, .sunday]
        return ShiftBundleTemplate(
            name: "Metro ED (from solve.py)",
            shifts: [
                ShiftTemplate(name: "West", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 8, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Acute", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 10, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Trauma", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 14, minute: 0), lengthHours: 10, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Overnight", location: "Metro", isOvernight: true, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 21, minute: 0), lengthHours: 48, daysOffered: overnightDays, active: true),
                ShiftTemplate(name: "Community Parma", location: "Parma", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 8, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Community Brecksville", location: "Brecksville", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 8, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "MLF Wayne", location: "Wayne", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 10, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "MLF Lorain", location: "Lorain", isOvernight: false, minShifts: nil, maxShifts: nil, startTime: LocalTime(hour: 7, minute: 0), lengthHours: 10, daysOffered: regularDays, active: true)
            ]
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
