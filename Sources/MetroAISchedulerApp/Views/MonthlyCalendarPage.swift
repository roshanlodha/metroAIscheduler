import SwiftUI
import UniformTypeIdentifiers

struct MonthlyCalendarPage: View {
    @Binding var result: ScheduleResult
    let students: [Student]
    let timezoneIdentifier: String
    let rules: GlobalScheduleRules
    let shiftTemplates: [ShiftTemplate]
    let shiftTypes: [ShiftType]
    let onExportAllICS: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var focusedWeekStart: Date = Date()
    @State private var rescheduleContext: RescheduleContext?
    @State private var constraintMessage: String?

    private let shiftColumnWidth: CGFloat = 260
    private let headerHeight: CGFloat = 42

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    private var studentByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    private var assignmentByShiftID: [String: Assignment] {
        Dictionary(uniqueKeysWithValues: result.assignments.map { ($0.shiftInstanceId, $0) })
    }

    private var shiftInstanceByID: [String: GeneratedShiftInstance] {
        Dictionary(uniqueKeysWithValues: result.shiftInstances.map { ($0.id, $0) })
    }

    private var shiftTemplateByID: [UUID: ShiftTemplate] {
        Dictionary(uniqueKeysWithValues: shiftTemplates.map { ($0.id, $0) })
    }

    private var studentColorByID: [UUID: Color] {
        let palette = ShiftTypeColor.allCases.map(\.swatchColor)
        guard !palette.isEmpty else { return [:] }
        let orderedStudents = students.sorted { lhs, rhs in
            let lhsKey = "\(lhs.displayName.lowercased())|\(lhs.email.lowercased())|\(lhs.id.uuidString)"
            let rhsKey = "\(rhs.displayName.lowercased())|\(rhs.email.lowercased())|\(rhs.id.uuidString)"
            return lhsKey < rhsKey
        }

        var mapping: [UUID: Color] = [:]
        for (index, student) in orderedStudents.enumerated() {
            mapping[student.id] = palette[index % palette.count]
        }
        return mapping
    }

    private var shiftTypeByID: [UUID: ShiftType] {
        Dictionary(uniqueKeysWithValues: shiftTypes.map { ($0.id, $0) })
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: focusedWeekStart)
        }
    }

    private var rows: [ShiftRow] {
        shiftTemplates
            .map { template in
                let typeName = template.shiftTypeId
                    .flatMap { shiftTypeByID[$0] }
                    .map { $0.name }
                    ?? "Unassigned"
                return ShiftRow(template: template, typeName: typeName)
            }
            .sorted { lhs, rhs in
                let lhsMinutes = lhs.template.startTime.hour * 60 + lhs.template.startTime.minute
                let rhsMinutes = rhs.template.startTime.hour * 60 + rhs.template.startTime.minute
                if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
                let typeCompare = lhs.typeName.localizedCaseInsensitiveCompare(rhs.typeName)
                if typeCompare != .orderedSame { return typeCompare == .orderedAscending }
                return lhs.template.name.localizedCaseInsensitiveCompare(rhs.template.name) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            if let constraintMessage {
                Text(constraintMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GeometryReader { geometry in
                let dayWidth = max(96, (geometry.size.width - shiftColumnWidth) / 7)
                let computedRowHeight = max(36, min(60, (geometry.size.height - headerHeight) / CGFloat(max(rows.count, 1))))

                VStack(spacing: 0) {
                    headerRow(dayWidth: dayWidth)
                    ForEach(rows) { row in
                        rowView(row: row, dayWidth: dayWidth, rowHeight: computedRowHeight)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }

            HStack {
                Button("Download All ICS") {
                    onExportAllICS()
                }
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(18)
        .frame(minWidth: 1080, minHeight: 640)
        .onAppear {
            if let minDate = result.shiftInstances.map(\.startDateTime).min() {
                focusedWeekStart = startOfWeek(for: minDate)
            } else {
                focusedWeekStart = startOfWeek(for: Date())
            }
        }
        .sheet(item: $rescheduleContext) { context in
            rescheduleSheet(sourceShiftInstanceID: context.sourceShiftInstanceID)
        }
    }

    private var header: some View {
        HStack {
            Text("Weekly Shift Calendar")
                .font(.title3)

            Spacer()

            Button {
                if let previous = calendar.date(byAdding: .day, value: -7, to: focusedWeekStart) {
                    focusedWeekStart = previous
                }
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(weekRangeLabel)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 420)

            Button {
                if let next = calendar.date(byAdding: .day, value: 7, to: focusedWeekStart) {
                    focusedWeekStart = next
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var weekRangeLabel: String {
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: focusedWeekStart) else {
            return monthDayYearLabel(for: focusedWeekStart)
        }

        let sameMonth = calendar.component(.month, from: focusedWeekStart) == calendar.component(.month, from: weekEnd)
        let sameYear = calendar.component(.year, from: focusedWeekStart) == calendar.component(.year, from: weekEnd)

        if sameMonth && sameYear {
            return "\(monthWideLabel(for: focusedWeekStart)) \(dayLabel(for: focusedWeekStart))-\(dayLabel(for: weekEnd)), \(yearLabel(for: focusedWeekStart))"
        }

        return "\(monthDayLabel(for: focusedWeekStart)) - \(monthDayYearLabel(for: weekEnd))"
    }

    private func headerRow(dayWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("Shift")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(width: shiftColumnWidth, height: headerHeight, alignment: .leading)
                .background(Color(nsColor: .underPageBackgroundColor))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))

            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(weekdayLabel(for: day))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(monthDayLabel(for: day))
                        .font(.caption.weight(.medium))
                }
                .frame(width: dayWidth, height: headerHeight)
                .background(Color(nsColor: .underPageBackgroundColor))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
    }

    @ViewBuilder
    private func rowView(row: ShiftRow, dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.template.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(row.typeName) • \(timeLabel(for: row.template))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(width: shiftColumnWidth, height: rowHeight, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))

            ForEach(weekDays, id: \.self) { day in
                if let instance = shiftInstance(for: row, day: day) {
                    let assignment = assignmentByShiftID[instance.id]
                    dropTargetCell(
                        instance: instance,
                        assignment: assignment,
                        dayWidth: dayWidth,
                        rowHeight: rowHeight
                    )
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: dayWidth, height: rowHeight)
                        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
            }
        }
    }

    @ViewBuilder
    private func dropTargetCell(
        instance: GeneratedShiftInstance,
        assignment: Assignment?,
        dayWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        Group {
            if let assignment, let cell = cellData(assignment: assignment, instance: instance) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(cell.studentName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(cell.timeLabel)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(width: dayWidth, height: rowHeight, alignment: .leading)
                .background(cell.color.opacity(0.9))
                .foregroundStyle(.white)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .onDrag {
                    NSItemProvider(object: NSString(string: instance.id))
                }
                .onTapGesture {
                    rescheduleContext = RescheduleContext(sourceShiftInstanceID: instance.id)
                }
            } else {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: dayWidth, height: rowHeight)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleDrop(providers: providers, targetShiftInstanceID: instance.id)
        }
    }

    private func handleDrop(providers: [NSItemProvider], targetShiftInstanceID: String) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let sourceShiftInstanceID = value as? NSString else { return }
            DispatchQueue.main.async {
                moveOrSwapAssignment(from: String(sourceShiftInstanceID), to: targetShiftInstanceID)
            }
        }
        return true
    }

    private func moveOrSwapAssignment(from sourceShiftInstanceID: String, to targetShiftInstanceID: String) {
        guard sourceShiftInstanceID != targetShiftInstanceID else { return }
        guard let candidateAssignments = assignmentsAfterMoveOrSwap(
            sourceShiftInstanceID: sourceShiftInstanceID,
            targetShiftInstanceID: targetShiftInstanceID,
            baseAssignments: result.assignments
        ) else {
            return
        }
        guard satisfiesScheduleConstraints(assignments: candidateAssignments) else {
            constraintMessage = "Reschedule blocked: this change violates schedule constraints."
            return
        }
        result.assignments = candidateAssignments
        constraintMessage = nil
    }

    @ViewBuilder
    private func rescheduleSheet(sourceShiftInstanceID: String) -> some View {
        let sourceCandidates = rescheduleCandidates(for: sourceShiftInstanceID)
        if let sourceAssignment = assignmentByShiftID[sourceShiftInstanceID],
           let sourceInstance = shiftInstanceByID[sourceShiftInstanceID] {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reschedule Shift")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text(studentName(for: sourceAssignment.studentId))
                        .font(.headline)
                    Text("\(sourceInstance.name) • \(monthDayLabel(for: sourceInstance.startDateTime)) • \(shortTimeRange(start: sourceInstance.startDateTime, end: sourceInstance.endDateTime))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    rescheduleCandidateColumn(
                        title: "Available Shifts",
                        actionLabel: "Move",
                        sourceShiftInstanceID: sourceShiftInstanceID,
                        candidateShiftInstances: sourceCandidates.available
                    )
                    rescheduleCandidateColumn(
                        title: "Filled Shifts",
                        actionLabel: "Swap",
                        sourceShiftInstanceID: sourceShiftInstanceID,
                        candidateShiftInstances: sourceCandidates.filled
                    )
                }
                .frame(maxHeight: .infinity, alignment: .top)

                if sourceCandidates.available.isEmpty && sourceCandidates.filled.isEmpty {
                    Text("No valid reschedule targets found without violating constraints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Close") { rescheduleContext = nil }
                }
            }
            .padding(18)
            .frame(minWidth: 840, minHeight: 520)
        } else {
            VStack(spacing: 12) {
                Text("Shift assignment no longer exists.")
                    .foregroundStyle(.secondary)
                Button("Close") { rescheduleContext = nil }
            }
            .padding(18)
        }
    }

    private func rescheduleCandidateColumn(
        title: String,
        actionLabel: String,
        sourceShiftInstanceID: String,
        candidateShiftInstances: [GeneratedShiftInstance]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(candidateShiftInstances) { instance in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(instance.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(weekdayLabel(for: instance.startDateTime)), \(monthDayLabel(for: instance.startDateTime))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(shortTimeRange(start: instance.startDateTime, end: instance.endDateTime))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let assignment = assignmentByShiftID[instance.id] {
                                Text("Assigned: \(studentName(for: assignment.studentId))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Spacer()
                                Button(actionLabel) {
                                    moveOrSwapAssignment(from: sourceShiftInstanceID, to: instance.id)
                                    if constraintMessage == nil {
                                        rescheduleContext = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .underPageBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rescheduleCandidates(for sourceShiftInstanceID: String) -> (available: [GeneratedShiftInstance], filled: [GeneratedShiftInstance]) {
        let sourceStart = shiftInstanceByID[sourceShiftInstanceID]?.startDateTime ?? .distantPast
        let assignedShiftIDs = Set(result.assignments.map(\.shiftInstanceId))
        let orderedInstances = result.shiftInstances.sorted {
            if $0.startDateTime != $1.startDateTime { return $0.startDateTime < $1.startDateTime }
            return $0.id < $1.id
        }

        let available = orderedInstances.filter { instance in
            instance.id != sourceShiftInstanceID &&
            !assignedShiftIDs.contains(instance.id) &&
            isRescheduleCandidateAllowed(sourceShiftInstanceID: sourceShiftInstanceID, targetShiftInstanceID: instance.id)
        }

        let filled = orderedInstances.filter { instance in
            instance.id != sourceShiftInstanceID &&
            assignedShiftIDs.contains(instance.id) &&
            isRescheduleCandidateAllowed(sourceShiftInstanceID: sourceShiftInstanceID, targetShiftInstanceID: instance.id)
        }

        return (
            available.sorted(by: { abs($0.startDateTime.timeIntervalSince(sourceStart)) < abs($1.startDateTime.timeIntervalSince(sourceStart)) }),
            filled.sorted(by: { abs($0.startDateTime.timeIntervalSince(sourceStart)) < abs($1.startDateTime.timeIntervalSince(sourceStart)) })
        )
    }

    private func isRescheduleCandidateAllowed(sourceShiftInstanceID: String, targetShiftInstanceID: String) -> Bool {
        guard let candidateAssignments = assignmentsAfterMoveOrSwap(
            sourceShiftInstanceID: sourceShiftInstanceID,
            targetShiftInstanceID: targetShiftInstanceID,
            baseAssignments: result.assignments
        ) else {
            return false
        }
        return satisfiesScheduleConstraints(assignments: candidateAssignments)
    }

    private func assignmentsAfterMoveOrSwap(
        sourceShiftInstanceID: String,
        targetShiftInstanceID: String,
        baseAssignments: [Assignment]
    ) -> [Assignment]? {
        guard sourceShiftInstanceID != targetShiftInstanceID else { return nil }
        guard let sourceIndex = baseAssignments.firstIndex(where: { $0.shiftInstanceId == sourceShiftInstanceID }) else {
            return nil
        }

        var updatedAssignments = baseAssignments
        let sourceStudentID = updatedAssignments[sourceIndex].studentId

        if let targetIndex = updatedAssignments.firstIndex(where: { $0.shiftInstanceId == targetShiftInstanceID }) {
            let targetStudentID = updatedAssignments[targetIndex].studentId
            updatedAssignments[sourceIndex].studentId = targetStudentID
            updatedAssignments[targetIndex].studentId = sourceStudentID
        } else {
            updatedAssignments[sourceIndex].shiftInstanceId = targetShiftInstanceID
        }
        return updatedAssignments
    }

    private func satisfiesScheduleConstraints(assignments: [Assignment]) -> Bool {
        let timezone = TimeZone(identifier: timezoneIdentifier) ?? .current
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timezone

        let studentIDs = Set(students.map(\.id))
        for assignment in assignments {
            if !studentIDs.contains(assignment.studentId) { return false }
            if shiftInstanceByID[assignment.shiftInstanceId] == nil { return false }
        }

        if rules.noDoubleBooking {
            var assignedShiftIDs: Set<String> = []
            for assignment in assignments {
                if assignedShiftIDs.contains(assignment.shiftInstanceId) {
                    return false
                }
                assignedShiftIDs.insert(assignment.shiftInstanceId)
            }
        }

        let overnightTypeIDs = Set(
            shiftTypes
                .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "overnight" }
                .map(\.id)
        )
        let overnightRequired = max(
            0,
            shiftTypes
                .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "overnight" }
                .compactMap(\.minShifts)
                .max() ?? 0
        )
        let requiredAssignmentsPerStudent = max(0, rules.numShiftsRequired - max(0, overnightRequired - 1))
        let dayBeforeConference = rules.conferenceDay == .sunday
            ? Weekday.saturday
            : Weekday(rawValue: rules.conferenceDay.rawValue - 1)

        var assignmentsByStudent: [UUID: [GeneratedShiftInstance]] = [:]
        for assignment in assignments {
            guard let shift = shiftInstanceByID[assignment.shiftInstanceId] else { return false }
            assignmentsByStudent[assignment.studentId, default: []].append(shift)

            if overlapsConference(shift: shift, calendar: localCalendar, rules: rules, timezone: timezone) {
                return false
            }

            if let template = shiftTemplateByID[shift.templateId],
               let typeID = template.shiftTypeId,
               overnightTypeIDs.contains(typeID),
               let shiftWeekday = Weekday(rawValue: localCalendar.component(.weekday, from: shift.startDateTime)),
               let dayBeforeConference,
               shiftWeekday == dayBeforeConference {
                return false
            }
        }

        for student in students {
            let studentShifts = assignmentsByStudent[student.id, default: []]
            if studentShifts.count != requiredAssignmentsPerStudent { return false }

            let sorted = studentShifts.sorted { $0.startDateTime < $1.startDateTime }
            for index in 0..<sorted.count {
                for secondIndex in (index + 1)..<sorted.count {
                    let first = sorted[index]
                    let second = sorted[secondIndex]
                    let overlaps = first.startDateTime < second.endDateTime && second.startDateTime < first.endDateTime
                    if overlaps { return false }

                    let restSeconds: TimeInterval
                    if first.endDateTime <= second.startDateTime {
                        restSeconds = second.startDateTime.timeIntervalSince(first.endDateTime)
                    } else {
                        restSeconds = first.startDateTime.timeIntervalSince(second.endDateTime)
                    }
                    if restSeconds < TimeInterval(max(0, rules.timeOffHours) * 3600) {
                        return false
                    }
                }
            }

            var perTypeCounts: [UUID: Int] = [:]
            var overnightShifts: [GeneratedShiftInstance] = []
            for shift in studentShifts {
                guard let template = shiftTemplateByID[shift.templateId] else { continue }
                if let typeID = template.shiftTypeId {
                    perTypeCounts[typeID, default: 0] += 1
                    if overnightTypeIDs.contains(typeID) {
                        overnightShifts.append(shift)
                    }
                }
            }

            for shiftType in shiftTypes {
                let count = perTypeCounts[shiftType.id, default: 0]
                if let minShifts = shiftType.minShifts, count < minShifts { return false }
                if let maxShifts = shiftType.maxShifts, count > maxShifts { return false }
            }

            if overnightRequired > 0 && overnightShifts.count != overnightRequired {
                return false
            }

            if overnightRequired > 1 {
                let sortedOvernights = overnightShifts.sorted { $0.startDateTime < $1.startDateTime }
                for index in 1..<sortedOvernights.count {
                    let previousStart = sortedOvernights[index - 1].startDateTime
                    let currentStart = sortedOvernights[index].startDateTime
                    if currentStart.timeIntervalSince(previousStart) != 86_400 {
                        return false
                    }
                }

                if let first = sortedOvernights.first, let last = sortedOvernights.last {
                    for shift in sorted where !sortedOvernights.contains(shift) {
                        if shift.startDateTime < last.endDateTime && first.startDateTime < shift.endDateTime {
                            return false
                        }
                    }
                }
            }
        }

        return true
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

    private func studentName(for id: UUID) -> String {
        guard let student = studentByID[id] else { return "Unknown Student" }
        return student.displayName.isEmpty ? student.email : student.displayName
    }

    private func shiftInstance(for row: ShiftRow, day: Date) -> GeneratedShiftInstance? {
        result.shiftInstances.first(where: {
            $0.templateId == row.template.id && calendar.isDate($0.startDateTime, inSameDayAs: day)
        })
    }

    private func cellData(assignment: Assignment, instance: GeneratedShiftInstance) -> GridCellData? {
        let student = studentByID[assignment.studentId]
        let studentName = (student?.displayName.isEmpty == false ? student?.displayName : student?.email) ?? "Unassigned"
        return GridCellData(
            studentName: studentName,
            timeLabel: shortTimeRange(start: instance.startDateTime, end: instance.endDateTime),
            color: studentColorByID[assignment.studentId] ?? .gray
        )
    }

    private func timeLabel(for template: ShiftTemplate) -> String {
        let start = String(format: "%02d:%02d", template.startTime.hour, template.startTime.minute)
        if let end = template.endTime {
            return "\(start)-\(String(format: "%02d:%02d", end.hour, end.minute))"
        }
        if let hours = template.lengthHours {
            return "\(start)+\(hours)h"
        }
        return start
    }

    private func shortTimeRange(start: Date, end: Date) -> String {
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return "\(start.formatted(formatter))-\(end.formatted(formatter))"
    }

    private func weekdayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func monthDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func monthDayYearLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func monthWideLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.string(from: date)
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func yearLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

private struct ShiftRow: Identifiable {
    let template: ShiftTemplate
    let typeName: String

    var id: UUID { template.id }
}

private struct GridCellData {
    let studentName: String
    let timeLabel: String
    let color: Color
}

private struct RescheduleContext: Identifiable {
    let sourceShiftInstanceID: String
    var id: String { sourceShiftInstanceID }
}
