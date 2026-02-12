import SwiftUI
import UniformTypeIdentifiers

struct MonthlyCalendarPage: View {
    @Binding var result: ScheduleResult
    let students: [Student]
    let timezoneIdentifier: String
    let shiftTemplates: [ShiftTemplate]
    let shiftTypes: [ShiftType]

    @Environment(\.dismiss) private var dismiss
    @State private var focusedWeekStart: Date = Date()
    @State private var selectedStudentIDs: Set<UUID> = []

    private let dayCellHeight: CGFloat = 470

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    private var studentByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    private var orderedStudents: [Student] {
        students.sorted {
            let left = $0.displayName.isEmpty ? $0.email : $0.displayName
            let right = $1.displayName.isEmpty ? $1.email : $1.displayName
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private var assignedStudentByShiftID: [String: Student] {
        var map: [String: Student] = [:]
        for assignment in result.assignments {
            guard let student = studentByID[assignment.studentId] else { continue }
            map[assignment.shiftInstanceId] = student
        }
        return map
    }

    private var shiftTypeByID: [UUID: ShiftType] {
        Dictionary(uniqueKeysWithValues: shiftTypes.map { ($0.id, $0) })
    }

    private var shiftTemplateByID: [UUID: ShiftTemplate] {
        Dictionary(uniqueKeysWithValues: shiftTemplates.map { ($0.id, $0) })
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: focusedWeekStart)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            studentLegend

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { day in
                        weekdayHeader(for: day)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { day in
                        DayCell(
                            day: day,
                            isToday: calendar.isDateInToday(day),
                            shifts: shifts(on: day),
                            timezoneIdentifier: timezoneIdentifier,
                            onDropShift: moveShift
                        )
                        .frame(maxWidth: .infinity, minHeight: dayCellHeight, maxHeight: dayCellHeight)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            HStack {
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
            if selectedStudentIDs.isEmpty {
                selectedStudentIDs = Set(students.map(\.id))
            }
        }
        .onChange(of: students.map(\.id)) { _, ids in
            let incoming = Set(ids)
            let retained = selectedStudentIDs.intersection(incoming)
            let newIDs = incoming.subtracting(selectedStudentIDs)
            selectedStudentIDs = retained.union(newIDs)
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
                .frame(minWidth: 320)

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
            return focusedWeekStart.formatted(.dateTime.month(.abbreviated).day().year())
        }

        let sameMonth = calendar.component(.month, from: focusedWeekStart) == calendar.component(.month, from: weekEnd)
        let sameYear = calendar.component(.year, from: focusedWeekStart) == calendar.component(.year, from: weekEnd)

        if sameMonth && sameYear {
            return "\(focusedWeekStart.formatted(.dateTime.month(.wide))) \(focusedWeekStart.formatted(.dateTime.day()))-\(weekEnd.formatted(.dateTime.day())), \(focusedWeekStart.formatted(.dateTime.year()))"
        }

        return "\(focusedWeekStart.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var studentLegend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(orderedStudents) { student in
                    StudentLegendToggle(
                        name: student.displayName.isEmpty ? student.email : student.displayName,
                        isOn: studentSelectionBinding(for: student.id)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func studentSelectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedStudentIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedStudentIDs.insert(id)
                } else {
                    selectedStudentIDs.remove(id)
                }
            }
        )
    }

    @ViewBuilder
    private func weekdayHeader(for day: Date) -> some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func shifts(on day: Date) -> [CalendarShift] {
        result.shiftInstances
            .filter { calendar.isDate($0.startDateTime, inSameDayAs: day) }
            .sorted { $0.startDateTime < $1.startDateTime }
            .compactMap { instance in
                guard let student = assignedStudentByShiftID[instance.id] else { return nil }
                guard selectedStudentIDs.contains(student.id) else { return nil }

                let template = shiftTemplateByID[instance.templateId]
                let typeColor = template
                    .flatMap { $0.shiftTypeId }
                    .flatMap { shiftTypeByID[$0] }
                    .map { $0.color.swatchColor } ?? .gray

                return CalendarShift(
                    id: instance.id,
                    shiftName: instance.name,
                    start: instance.startDateTime,
                    end: instance.endDateTime,
                    studentName: student.displayName.isEmpty ? student.email : student.displayName,
                    color: typeColor
                )
            }
    }

    private func moveShift(_ shiftID: String, to targetDay: Date) {
        guard let index = result.shiftInstances.firstIndex(where: { $0.id == shiftID }) else { return }

        let current = result.shiftInstances[index]
        let currentDayStart = calendar.startOfDay(for: current.startDateTime)
        let targetDayStart = calendar.startOfDay(for: targetDay)
        let dayDelta = calendar.dateComponents([.day], from: currentDayStart, to: targetDayStart).day ?? 0
        guard dayDelta != 0 else { return }

        guard let nextStart = calendar.date(byAdding: .day, value: dayDelta, to: current.startDateTime) else { return }
        let duration = current.endDateTime.timeIntervalSince(current.startDateTime)
        result.shiftInstances[index].startDateTime = nextStart
        result.shiftInstances[index].endDateTime = nextStart.addingTimeInterval(duration)
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}

private struct StudentLegendToggle: View {
    let name: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .toggleStyle(.checkbox)
    }
}

private struct DayCell: View {
    let day: Date
    let isToday: Bool
    let shifts: [CalendarShift]
    let timezoneIdentifier: String
    let onDropShift: (String, Date) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(.primary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shifts) { shift in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shift.studentName)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text("\(shift.shiftName) • \(timeLabel(start: shift.start, end: shift.end))")
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(shift.color.opacity(0.93))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .draggable(shift.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(6)
        .background(cellBackground)
        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let stringValue: String?
                if let data = item as? Data {
                    stringValue = String(data: data, encoding: .utf8)
                } else if let text = item as? String {
                    stringValue = text
                } else if let nsText = item as? NSString {
                    stringValue = nsText as String
                } else {
                    stringValue = nil
                }

                guard let shiftID = stringValue else { return }
                DispatchQueue.main.async {
                    onDropShift(shiftID, day)
                }
            }
            return true
        }
    }

    private var cellBackground: Color {
        if isDropTarget {
            return Color.accentColor.opacity(0.16)
        }
        if isToday {
            return Color.accentColor.opacity(0.08)
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    private func timeLabel(start: Date, end: Date) -> String {
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return "\(start.formatted(formatter))-\(end.formatted(formatter))"
    }
}

private struct CalendarShift: Identifiable {
    let id: String
    let shiftName: String
    let start: Date
    let end: Date
    let studentName: String
    let color: Color
}
