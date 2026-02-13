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

    var fullName: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
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
    var shiftTypeId: UUID?
    var startTime: LocalTime
    var endTime: LocalTime?
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
        shiftTypeId: UUID? = nil,
        startTime: LocalTime = LocalTime(),
        endTime: LocalTime? = LocalTime(hour: 16, minute: 0),
        lengthHours: Int? = nil,
        daysOffered: Set<Weekday> = Set(Weekday.allCases),
        active: Bool = true
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.isOvernight = isOvernight
        self.minShifts = minShifts
        self.maxShifts = maxShifts
        self.shiftTypeId = shiftTypeId
        self.startTime = startTime
        self.endTime = endTime
        self.lengthHours = lengthHours
        self.daysOffered = daysOffered
        self.active = active
    }
}

struct ShiftType: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var minShifts: Int?
    var maxShifts: Int?
    var color: ShiftTypeColor

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case minShifts
        case maxShifts
        case color
    }

    init(
        id: UUID = UUID(),
        name: String,
        minShifts: Int? = nil,
        maxShifts: Int? = nil,
        color: ShiftTypeColor = .blue
    ) {
        self.id = id
        self.name = name
        self.minShifts = minShifts
        self.maxShifts = maxShifts
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        minShifts = try container.decodeIfPresent(Int.self, forKey: .minShifts)
        maxShifts = try container.decodeIfPresent(Int.self, forKey: .maxShifts)
        color = try container.decodeIfPresent(ShiftTypeColor.self, forKey: .color) ?? .blue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(minShifts, forKey: .minShifts)
        try container.encodeIfPresent(maxShifts, forKey: .maxShifts)
        try container.encode(color, forKey: .color)
    }
}

enum ShiftTypeColor: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case brown

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?.lowercased() ?? "blue"
        switch rawValue {
        case "red":
            self = .red
        case "orange":
            self = .orange
        case "yellow":
            self = .yellow
        case "green":
            self = .green
        case "blue", "teal":
            self = .blue
        case "purple", "indigo":
            self = .purple
        case "brown":
            self = .brown
        case "pink":
            self = .red
        default:
            self = .blue
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ShiftBundleTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shifts: [ShiftTemplate]
    var shiftTypes: [ShiftType]?

    init(id: UUID = UUID(), name: String, shifts: [ShiftTemplate], shiftTypes: [ShiftType]? = nil) {
        self.id = id
        self.name = name
        self.shifts = shifts
        self.shiftTypes = shiftTypes
    }
}

struct GlobalScheduleRules: Codable, Equatable {
    var timeOffHours: Int
    var numShiftsRequired: Int
    var timezone: String
    var noDoubleBooking: Bool
    var blockStartDay: Weekday
    var conferenceDay: Weekday
    var conferenceStartTime: LocalTime
    var conferenceEndTime: LocalTime
    var solverTimeLimitSeconds: Int

    static var `default`: GlobalScheduleRules {
        GlobalScheduleRules(
            timeOffHours: 10,
            numShiftsRequired: 14,
            timezone: "America/New_York",
            noDoubleBooking: true,
            blockStartDay: .monday,
            conferenceDay: .wednesday,
            conferenceStartTime: LocalTime(hour: 8, minute: 0),
            conferenceEndTime: LocalTime(hour: 12, minute: 0),
            solverTimeLimitSeconds: 20
        )
    }

    enum CodingKeys: String, CodingKey {
        case timeOffHours
        case numShiftsRequired
        case timezone
        case noDoubleBooking
        case blockStartDay
        case conferenceDay
        case conferenceStartTime
        case conferenceEndTime
        case solverTimeLimitSeconds
        case allowOvernightBeforeWednesday
    }

    init(
        timeOffHours: Int,
        numShiftsRequired: Int,
        timezone: String,
        noDoubleBooking: Bool,
        blockStartDay: Weekday,
        conferenceDay: Weekday,
        conferenceStartTime: LocalTime,
        conferenceEndTime: LocalTime,
        solverTimeLimitSeconds: Int
    ) {
        self.timeOffHours = timeOffHours
        self.numShiftsRequired = numShiftsRequired
        self.timezone = timezone
        self.noDoubleBooking = noDoubleBooking
        self.blockStartDay = blockStartDay
        self.conferenceDay = conferenceDay
        self.conferenceStartTime = conferenceStartTime
        self.conferenceEndTime = conferenceEndTime
        self.solverTimeLimitSeconds = solverTimeLimitSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeOffHours = try container.decode(Int.self, forKey: .timeOffHours)
        numShiftsRequired = try container.decode(Int.self, forKey: .numShiftsRequired)
        timezone = try container.decode(String.self, forKey: .timezone)
        noDoubleBooking = try container.decode(Bool.self, forKey: .noDoubleBooking)
        blockStartDay = try container.decodeIfPresent(Weekday.self, forKey: .blockStartDay) ?? .monday
        solverTimeLimitSeconds = try container.decode(Int.self, forKey: .solverTimeLimitSeconds)

        if let conferenceDay = try container.decodeIfPresent(Weekday.self, forKey: .conferenceDay) {
            self.conferenceDay = conferenceDay
        } else {
            let legacyAllow = try container.decodeIfPresent(Bool.self, forKey: .allowOvernightBeforeWednesday) ?? false
            self.conferenceDay = legacyAllow ? .sunday : .wednesday
        }
        conferenceStartTime = try container.decodeIfPresent(LocalTime.self, forKey: .conferenceStartTime) ?? LocalTime(hour: 8, minute: 0)
        conferenceEndTime = try container.decodeIfPresent(LocalTime.self, forKey: .conferenceEndTime) ?? LocalTime(hour: 12, minute: 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeOffHours, forKey: .timeOffHours)
        try container.encode(numShiftsRequired, forKey: .numShiftsRequired)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(noDoubleBooking, forKey: .noDoubleBooking)
        try container.encode(blockStartDay, forKey: .blockStartDay)
        try container.encode(conferenceDay, forKey: .conferenceDay)
        try container.encode(conferenceStartTime, forKey: .conferenceStartTime)
        try container.encode(conferenceEndTime, forKey: .conferenceEndTime)
        try container.encode(solverTimeLimitSeconds, forKey: .solverTimeLimitSeconds)
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

struct OrientationWindow: Codable, Equatable {
    var startDate: Date
    var startTime: LocalTime
    var endTime: LocalTime

    static func `default`(startDate: Date) -> OrientationWindow {
        OrientationWindow(
            startDate: startDate,
            startTime: LocalTime(hour: 8, minute: 0),
            endTime: LocalTime(hour: 12, minute: 0)
        )
    }
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
    var shiftTypes: [ShiftType]
    var templateLibrary: [ShiftBundleTemplate]
    var students: [Student]
    var defaultStudentCount: Int
    var orientation: OrientationWindow
    var rules: GlobalScheduleRules
    var blockWindow: BlockWindow

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case name
        case shiftTemplates
        case shiftTypes
        case templateLibrary
        case students
        case defaultStudentCount
        case orientation
        case rules
        case blockWindow
    }

    init(
        schemaVersion: Int,
        name: String,
        shiftTemplates: [ShiftTemplate],
        shiftTypes: [ShiftType],
        templateLibrary: [ShiftBundleTemplate],
        students: [Student],
        defaultStudentCount: Int,
        orientation: OrientationWindow,
        rules: GlobalScheduleRules,
        blockWindow: BlockWindow
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.shiftTemplates = shiftTemplates
        self.shiftTypes = shiftTypes
        self.templateLibrary = templateLibrary
        self.students = students
        self.defaultStudentCount = defaultStudentCount
        self.orientation = orientation
        self.rules = rules
        self.blockWindow = blockWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        shiftTemplates = try container.decodeIfPresent([ShiftTemplate].self, forKey: .shiftTemplates) ?? []
        shiftTypes = try container.decodeIfPresent([ShiftType].self, forKey: .shiftTypes) ?? []
        templateLibrary = try container.decodeIfPresent([ShiftBundleTemplate].self, forKey: .templateLibrary) ?? []
        students = try container.decodeIfPresent([Student].self, forKey: .students) ?? []
        defaultStudentCount = try container.decodeIfPresent(Int.self, forKey: .defaultStudentCount) ?? 0
        blockWindow = try container.decode(BlockWindow.self, forKey: .blockWindow)
        orientation = try container.decodeIfPresent(OrientationWindow.self, forKey: .orientation) ?? .default(startDate: blockWindow.startDate)
        rules = try container.decodeIfPresent(GlobalScheduleRules.self, forKey: .rules) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(name, forKey: .name)
        try container.encode(shiftTemplates, forKey: .shiftTemplates)
        try container.encode(shiftTypes, forKey: .shiftTypes)
        try container.encode(templateLibrary, forKey: .templateLibrary)
        try container.encode(students, forKey: .students)
        try container.encode(defaultStudentCount, forKey: .defaultStudentCount)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(rules, forKey: .rules)
        try container.encode(blockWindow, forKey: .blockWindow)
    }

    static func empty(now: Date = Date()) -> ScheduleTemplateProject {
        let blockWindow = defaultBlockWindow(now: now, blockStartDay: GlobalScheduleRules.default.blockStartDay)
        return ScheduleTemplateProject(
            schemaVersion: 2,
            name: "Untitled Project",
            shiftTemplates: [],
            shiftTypes: [],
            templateLibrary: [MetroPresetFactory.metroEDTemplate()],
            students: [],
            defaultStudentCount: 0,
            orientation: .default(startDate: blockWindow.startDate),
            rules: .default,
            blockWindow: blockWindow
        )
    }

    static func sample(now: Date = Date()) -> ScheduleTemplateProject {
        let blockWindow = defaultBlockWindow(now: now, blockStartDay: GlobalScheduleRules.default.blockStartDay)
        let metroTemplate = MetroPresetFactory.metroEDTemplate()
        return ScheduleTemplateProject(
            schemaVersion: 2,
            name: "Sample Metro Project",
            shiftTemplates: metroTemplate.shifts,
            shiftTypes: MetroPresetFactory.metroShiftTypes(),
            templateLibrary: [metroTemplate],
            students: [
                Student(firstName: "Alex", lastName: "Kim", email: "alex@example.edu"),
                Student(firstName: "Jordan", lastName: "Patel", email: "jordan@example.edu")
            ],
            defaultStudentCount: 2,
            orientation: .default(startDate: blockWindow.startDate),
            rules: .default,
            blockWindow: blockWindow
        )
    }

    private static func defaultBlockWindow(now: Date, blockStartDay: Weekday) -> BlockWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: GlobalScheduleRules.default.timezone) ?? .current
        calendar.firstWeekday = 2

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let dayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        let offset = dayOrder.firstIndex(of: blockStartDay) ?? 0
        let start = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
        let end = calendar.date(byAdding: .day, value: 22, to: start) ?? start
        return BlockWindow(startDate: start, endDate: end)
    }
}

enum MetroPresetFactory {
    static func metroShiftTypes() -> [ShiftType] {
        [
            ShiftType(name: "West", minShifts: 1, maxShifts: nil, color: .blue),
            ShiftType(name: "Acute", minShifts: 2, maxShifts: nil, color: .green),
            ShiftType(name: "Trauma", minShifts: nil, maxShifts: nil, color: .orange),
            ShiftType(name: "Overnight", minShifts: 1, maxShifts: nil, color: .purple),
            ShiftType(name: "Community", minShifts: nil, maxShifts: 1, color: .red),
            ShiftType(name: "MLF", minShifts: nil, maxShifts: 1, color: .brown)
        ]
    }

    static func metroEDTemplate() -> ShiftBundleTemplate {
        let types = metroShiftTypes()
        let typeByName = Dictionary(uniqueKeysWithValues: types.map { ($0.name, $0.id) })
        let regularDays: Set<Weekday> = [.monday, .tuesday, .thursday, .friday, .saturday, .sunday]
        let overnightDays: Set<Weekday> = [.monday, .thursday, .friday, .saturday, .sunday]
        return ShiftBundleTemplate(
            name: "Metro ED (from solve.py)",
            shifts: [
                ShiftTemplate(name: "West", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["West"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 15, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Acute", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["Acute"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 17, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Trauma", location: "Metro", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["Trauma"], startTime: LocalTime(hour: 14, minute: 0), endTime: LocalTime(hour: 0, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Overnight", location: "Metro", isOvernight: true, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["Overnight"], startTime: LocalTime(hour: 21, minute: 0), endTime: LocalTime(hour: 7, minute: 0), lengthHours: nil, daysOffered: overnightDays, active: true),
                ShiftTemplate(name: "Community Parma", location: "Parma", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["Community"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 15, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "Community Brecksville", location: "Brecksville", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["Community"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 15, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "MLF Wayne", location: "Wayne", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["MLF"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 17, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true),
                ShiftTemplate(name: "MLF Lorain", location: "Lorain", isOvernight: false, minShifts: nil, maxShifts: nil, shiftTypeId: typeByName["MLF"], startTime: LocalTime(hour: 7, minute: 0), endTime: LocalTime(hour: 17, minute: 0), lengthHours: nil, daysOffered: regularDays, active: true)
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
