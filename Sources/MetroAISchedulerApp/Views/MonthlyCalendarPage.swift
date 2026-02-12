import SwiftUI
import UniformTypeIdentifiers

struct MonthlyCalendarPage: View {
    @Binding var result: ScheduleResult
    let students: [Student]
    let timezoneIdentifier: String

    @Environment(\.dismiss) private var dismiss
    @State private var focusedMonth: Date = Date()

    private let dayColumnWidth: CGFloat = 220
    private let dayCellHeight: CGFloat = 170

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        cal.firstWeekday = 2
        return cal
    }

    private var studentByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    private var assignedStudentByShiftID: [String: Student] {
        var map: [String: Student] = [:]
        for assignment in result.assignments {
            guard let student = studentByID[assignment.studentId] else { continue }
            map[assignment.shiftInstanceId] = student
        }
        return map
    }

    private var orderedStudents: [Student] {
        students.sorted {
            let left = $0.displayName.isEmpty ? $0.email : $0.displayName
            let right = $1.displayName.isEmpty ? $1.email : $1.displayName
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    private var studentColorByID: [UUID: Color] {
        let palette: [Color] = [
            Color(red: 0.16, green: 0.46, blue: 0.80),
            Color(red: 0.12, green: 0.66, blue: 0.47),
            Color(red: 0.88, green: 0.41, blue: 0.18),
            Color(red: 0.64, green: 0.29, blue: 0.74),
            Color(red: 0.82, green: 0.21, blue: 0.35),
            Color(red: 0.20, green: 0.62, blue: 0.72),
            Color(red: 0.58, green: 0.52, blue: 0.20),
            Color(red: 0.36, green: 0.41, blue: 0.89)
        ]

        var map: [UUID: Color] = [:]
        for (index, student) in orderedStudents.enumerated() {
            map[student.id] = palette[index % palette.count]
        }
        return map
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            legend

            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 0) {
                    weekdayHeaderRow
                    monthGrid
                }
                .frame(width: dayColumnWidth * 7)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(16)
        .frame(minWidth: 1100, minHeight: 760)
        .onAppear {
            if let minDate = result.shiftInstances.map(\.startDateTime).min() {
                focusedMonth = startOfMonth(for: minDate)
            } else {
                focusedMonth = startOfMonth(for: Date())
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Monthly Shift Calendar")
                .font(.title3)

            Spacer()

            Button {
                if let previous = calendar.date(byAdding: .month, value: -1, to: focusedMonth) {
                    focusedMonth = previous
                }
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(focusedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2.weight(.semibold))
                .frame(minWidth: 260)

            Button {
                if let next = calendar.date(byAdding: .month, value: 1, to: focusedMonth) {
                    focusedMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(orderedStudents) { student in
                    LegendChip(
                        name: student.displayName.isEmpty ? student.email : student.displayName,
                        color: studentColorByID[student.id] ?? .gray
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(dayColumnWidth), spacing: 0), count: 7), spacing: 0) {
            ForEach(weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: dayColumnWidth, height: 30)
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(dayColumnWidth), spacing: 0), count: 7), spacing: 0) {
            ForEach(monthGridDays, id: \.id) { entry in
                DayCell(
                    day: entry.day,
                    isCurrentMonth: entry.isCurrentMonth,
                    isToday: calendar.isDateInToday(entry.day),
                    shifts: shifts(on: entry.day),
                    timezoneIdentifier: timezoneIdentifier,
                    onDropShift: moveShift
                )
                .frame(width: dayColumnWidth, height: dayCellHeight)
            }
        }
    }

    private var weekdayLabels: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = max(0, calendar.firstWeekday - 1)
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var monthGridDays: [CalendarGridDay] {
        let monthStart = startOfMonth(for: focusedMonth)
        guard let daysRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var entries: [CalendarGridDay] = []

        for offset in stride(from: leadingCount, to: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { continue }
            entries.append(CalendarGridDay(day: day, isCurrentMonth: false))
        }

        for day in daysRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            entries.append(CalendarGridDay(day: date, isCurrentMonth: true))
        }

        while entries.count < 42 {
            guard let last = entries.last?.day,
                  let next = calendar.date(byAdding: .day, value: 1, to: last) else { break }
            entries.append(CalendarGridDay(day: next, isCurrentMonth: false))
        }

        return entries
    }

    private func shifts(on day: Date) -> [CalendarShift] {
        result.shiftInstances
            .filter { calendar.isDate($0.startDateTime, inSameDayAs: day) }
            .sorted { $0.startDateTime < $1.startDateTime }
            .compactMap { instance in
                guard let student = assignedStudentByShiftID[instance.id] else { return nil }
                return CalendarShift(
                    id: instance.id,
                    shiftName: instance.name,
                    start: instance.startDateTime,
                    end: instance.endDateTime,
                    studentName: student.displayName.isEmpty ? student.email : student.displayName,
                    color: studentColorByID[student.id] ?? .gray
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

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

private struct DayCell: View {
    let day: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let shifts: [CalendarShift]
    let timezoneIdentifier: String
    let onDropShift: (String, Date) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)

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
                        .background(shift.color.opacity(0.92))
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
        if isCurrentMonth {
            return Color(nsColor: .windowBackgroundColor)
        }
        return Color(nsColor: .underPageBackgroundColor)
    }

    private func timeLabel(start: Date, end: Date) -> String {
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return "\(start.formatted(formatter))-\(end.formatted(formatter))"
    }
}

private struct LegendChip: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(Capsule())
    }
}

private struct CalendarGridDay: Identifiable {
    let id = UUID()
    let day: Date
    let isCurrentMonth: Bool
}

private struct CalendarShift: Identifiable {
    let id: String
    let shiftName: String
    let start: Date
    let end: Date
    let studentName: String
    let color: Color
}
