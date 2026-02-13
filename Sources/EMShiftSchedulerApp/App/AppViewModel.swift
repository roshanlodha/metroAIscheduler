import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var project: ScheduleTemplateProject
    @Published var result: ScheduleResult?
    @Published var validationIssues: [ValidationIssue] = []
    @Published var statusMessage: String = "Ready"
    @Published var solverDiagnostic: SolverDiagnostic?
    @Published var isSolving: Bool = false

    private let solver: SolverAdapter

    init(solver: SolverAdapter = PythonSolverAdapter()) {
        self.project = ScheduleTemplateProject.empty()
        self.solver = solver
        validate()
    }

    func validate() {
        validationIssues = ProjectValidator.validate(project: project)
    }

    func createSchedule() {
        normalizeProject()
        validate()
        guard validationIssues.isEmpty else {
            statusMessage = "Fix validation issues before solving."
            return
        }

        let instances = ShiftExpansion.expand(project: project)
        let projectSnapshot = project
        let solverRef = solver
        isSolving = true
        statusMessage = "Generating schedule..."
        solverDiagnostic = nil

        Task.detached {
            do {
                let solved = try solverRef.solve(project: projectSnapshot, shiftInstances: instances)
                await MainActor.run {
                    let (sanitized, removed) = self.sanitizeAssignments(project: projectSnapshot, result: solved)
                    if removed > 0 {
                        self.result = nil
                        self.solverDiagnostic = SolverDiagnostic(
                            message: "No feasible assignment found.",
                            details: [
                                "The solver produced \(removed) assignment(s) that violate scheduling constraints.",
                                "No partial schedule is shown."
                            ]
                        )
                        self.statusMessage = "No feasible assignment found."
                    } else {
                        self.result = sanitized
                        self.statusMessage = "Schedule generated with \(sanitized.assignments.count) assignments."
                    }
                    self.isSolving = false
                }
            } catch let error as SolverError {
                await MainActor.run {
                    switch error {
                    case .infeasible(let diagnostic):
                        self.solverDiagnostic = diagnostic
                    default:
                        self.solverDiagnostic = SolverDiagnostic(message: "Solve failed", details: [error.localizedDescription])
                    }
                    self.statusMessage = "Failed to generate schedule."
                    self.isSolving = false
                }
            } catch {
                await MainActor.run {
                    self.solverDiagnostic = SolverDiagnostic(message: "Unexpected error", details: [error.localizedDescription])
                    self.statusMessage = "Failed to generate schedule."
                    self.isSolving = false
                }
            }
        }
    }

    func loadProject(from url: URL) {
        do {
            project = try ProjectStore.loadProject(from: url)
            normalizeProject()
            result = nil
            statusMessage = "Loaded project: \(project.name)"
            validate()
        } catch {
            statusMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    func saveProject(to url: URL) {
        do {
            normalizeProject()
            try ProjectStore.saveProject(project, to: url)
            statusMessage = "Project saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func saveResultJSON(to url: URL) {
        guard let result else { return }
        do {
            try ProjectStore.saveResult(result, to: url)
            statusMessage = "Result JSON exported."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func saveCSV(to url: URL) {
        guard let result else { return }
        do {
            try CSVExporter.export(project: project, result: result).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "CSV exported."
        } catch {
            statusMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }

    func saveICS(for student: Student, to url: URL) {
        guard let result else { return }
        do {
            try ICSExporter.export(for: student, project: project, result: result).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "ICS exported for \(student.displayName)."
        } catch {
            statusMessage = "ICS export failed: \(error.localizedDescription)"
        }
    }

    func saveAllICSArchive(to url: URL) {
        guard let result else { return }
        let exportStudents = project.students.filter { !isBlankStudent($0) }
        guard !exportStudents.isEmpty else {
            statusMessage = "Batch ICS export failed: no students to export."
            return
        }

        let fileManager = FileManager.default
        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("metro-ics-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

            for (index, student) in exportStudents.enumerated() {
                let name = sanitizedICSName(for: student, fallbackIndex: index + 1)
                let path = tempRoot.appendingPathComponent("\(name).ics", isDirectory: false)
                let ics = ICSExporter.export(for: student, project: project, result: result)
                try ics.write(to: path, atomically: true, encoding: .utf8)
            }

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-q", "-r", url.path, "."]
            process.currentDirectoryURL = tempRoot
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "EMShiftScheduler.ZipExport",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "zip command failed with code \(process.terminationStatus)"]
                )
            }

            statusMessage = "All student ICS files exported to \(url.lastPathComponent)."
        } catch {
            statusMessage = "Batch ICS export failed: \(error.localizedDescription)"
        }

        try? fileManager.removeItem(at: tempRoot)
    }

    func importShiftSchedule(from url: URL) {
        do {
            let bundle = try ProjectStore.loadShiftBundle(from: url)
            loadShiftBundle(bundle)
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func exportShiftSchedule(to url: URL) {
        do {
            let bundleName = project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shift Schedule" : project.name
            let bundle = ShiftBundleTemplate(name: bundleName, shifts: project.shiftTemplates, shiftTypes: project.shiftTypes)
            try ProjectStore.saveShiftBundle(bundle, to: url)
            statusMessage = "Shift schedule exported."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func loadShiftBundle(_ bundle: ShiftBundleTemplate) {
        if let importedTypes = bundle.shiftTypes, !importedTypes.isEmpty {
            project.shiftTypes = importedTypes
        } else if project.shiftTypes.isEmpty {
            project.shiftTypes = MetroPresetFactory.metroShiftTypes()
        }
        project.shiftTemplates = bundle.shifts.map { shift in
            var copy = shift
            copy.id = UUID()
            copy.active = true
            if copy.shiftTypeId == nil {
                copy.shiftTypeId = inferredTypeID(for: copy.name)
            }
            return copy
        }
        statusMessage = "Loaded template: \(bundle.name)"
        validate()
    }

    func saveCurrentShiftsAsTemplate(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Template name is required."
            return
        }
        let bundle = ShiftBundleTemplate(name: trimmed, shifts: project.shiftTemplates, shiftTypes: project.shiftTypes)
        project.templateLibrary.append(bundle)
        statusMessage = "Saved template: \(trimmed)"
    }

    func loadMetroPresetIntoCurrentShifts() {
        let preset = MetroPresetFactory.metroEDTemplate()
        project.shiftTypes = MetroPresetFactory.metroShiftTypes()
        project.shiftTemplates = preset.shifts.map { shift in
            var copy = shift
            copy.id = UUID()
            copy.active = true
            return copy
        }
        if !project.templateLibrary.contains(where: { $0.name == preset.name }) {
            project.templateLibrary.append(preset)
        }
        statusMessage = "Loaded Metro preset shifts."
        validate()
    }

    private func normalizeProject() {
        project.rules.timezone = TimeZone.current.identifier
        project.students.removeAll { student in
            student.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            student.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        normalizeShiftTypes()
        project.shiftTemplates = project.shiftTemplates.map { shift in
            var copy = shift
            copy.active = true
            if copy.shiftTypeId == nil {
                copy.shiftTypeId = inferredTypeID(for: copy.name)
            }
            return copy
        }
    }

    private func normalizeShiftTypes() {
        if project.shiftTypes.isEmpty {
            let inferredNames = Set(project.shiftTemplates.map { inferredTypeName(for: $0.name) })
            project.shiftTypes = inferredNames.sorted().map { ShiftType(name: $0, minShifts: nil, maxShifts: nil) }
        }
    }

    private func inferredTypeID(for shiftName: String) -> UUID? {
        let name = inferredTypeName(for: shiftName)
        return project.shiftTypes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id
    }

    private func inferredTypeName(for shiftName: String) -> String {
        let lower = shiftName.lowercased()
        if lower.contains("community") { return "Community" }
        if lower.contains("mlf") { return "MLF" }
        if lower.contains("overnight") || lower.contains("night") { return "Overnight" }
        if lower.contains("acute") { return "Acute" }
        if lower.contains("west") { return "West" }
        if lower.contains("trauma") { return "Trauma" }
        return shiftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General" : shiftName
    }

    private func sanitizedICSName(for student: Student, fallbackIndex: Int) -> String {
        let baseRaw = student.name
        let trimmed = baseRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        if cleaned.isEmpty {
            return "student_\(fallbackIndex)"
        }
        return cleaned
    }

    private func isBlankStudent(_ student: Student) -> Bool {
        student.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        student.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sanitizeAssignments(project: ScheduleTemplateProject, result: ScheduleResult) -> (ScheduleResult, Int) {
        guard let timezone = TimeZone(identifier: project.rules.timezone) else {
            return (result, 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let shiftByID = Dictionary(uniqueKeysWithValues: result.shiftInstances.map { ($0.id, $0) })
        let templateByID = Dictionary(uniqueKeysWithValues: project.shiftTemplates.map { ($0.id, $0) })
        let overnightTypeIDs = Set(
            project.shiftTypes
                .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "overnight" }
                .map(\.id)
        )

        let filtered = result.assignments.filter { assignment in
            guard let shift = shiftByID[assignment.shiftInstanceId],
                  let template = templateByID[shift.templateId] else {
                return false
            }
            let weekdayValue = calendar.component(.weekday, from: shift.startDateTime)
            guard let weekday = Weekday(rawValue: weekdayValue),
                  template.daysOffered.contains(weekday) else {
                return false
            }
            let isOvernightTypeShift = template.shiftTypeId.map { overnightTypeIDs.contains($0) } ?? false
            if isOvernightTypeShift && isDayBeforeConference(weekday: weekday, conferenceDay: project.rules.conferenceDay) {
                return false
            }
            if overlapsConference(shift: shift, calendar: calendar, rules: project.rules, timezone: timezone) {
                return false
            }
            return true
        }

        let removed = result.assignments.count - filtered.count
        return (
            ScheduleResult(
                generatedAt: result.generatedAt,
                shiftInstances: result.shiftInstances,
                assignments: filtered
            ),
            removed
        )
    }

    private func isDayBeforeConference(weekday: Weekday, conferenceDay: Weekday) -> Bool {
        let order: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        guard let weekdayIndex = order.firstIndex(of: weekday),
              let conferenceIndex = order.firstIndex(of: conferenceDay) else {
            return false
        }
        return (weekdayIndex + 1) % order.count == conferenceIndex
    }

    private func overlapsConference(
        shift: GeneratedShiftInstance,
        calendar: Calendar,
        rules: GlobalScheduleRules,
        timezone: TimeZone
    ) -> Bool {
        var day = calendar.startOfDay(for: shift.startDateTime)
        let endDay = calendar.startOfDay(for: shift.endDateTime)

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

                if shift.startDateTime < conferenceEnd && conferenceStart < shift.endDateTime {
                    return true
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return false
    }
}
