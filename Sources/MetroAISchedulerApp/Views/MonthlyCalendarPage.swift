import SwiftUI
import UniformTypeIdentifiers

struct MonthlyCalendarPage: View {
    @Binding var result: ScheduleResult
    let students: [Student]
    let timezoneIdentifier: String

    @Environment(\.dismiss) private var dismiss
    @State private var focusedMonth: Date = Date()

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return cal
    }

    private var studentByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthGridDays, id: \.id) { entry in
                    DayCell(
                        day: entry.day,
                        isCurrentMonth: entry.isCurrentMonth,
                        shifts: shifts(on: entry.day),
                        timezoneIdentifier: timezoneIdentifier,
                        onDropShift: moveShift
                    )
                }
            }

            Spacer()
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
            Button {
                if let previous = calendar.date(byAdding: .month, value: -1, to: focusedMonth) {
                    focusedMonth = previous
                }
            } label: {
                Image(systemName: "chevron.left")
            }

            Text(focusedMonth.formatted(.dateTime.year().month(.wide)))
                .font(.title2)
                .frame(maxWidth: .infinity)

            Button {
                if let next = calendar.date(byAdding: .month, value: 1, to: focusedMonth) {
                    focusedMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
            }

            Button("Done") {
                dismiss()
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

        let totalCount = leadingCount + daysRange.count
        let trailingCount = (7 - (totalCount % 7)) % 7

        var entries: [CalendarGridDay] = []

        if leadingCount > 0 {
            for offset in stride(from: leadingCount, to: 0, by: -1) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: monthStart) else { continue }
                entries.append(CalendarGridDay(day: day, isCurrentMonth: false))
            }
        }

        for day in daysRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            entries.append(CalendarGridDay(day: date, isCurrentMonth: true))
        }

        if trailingCount > 0 {
            guard let monthEnd = calendar.date(byAdding: .day, value: daysRange.count - 1, to: monthStart) else {
                return entries
            }
            for offset in 1...trailingCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: monthEnd) else { continue }
                entries.append(CalendarGridDay(day: day, isCurrentMonth: false))
            }
        }

        return entries
    }

    private func shifts(on day: Date) -> [CalendarShift] {
        var assignedStudent: [String: Student] = [:]
        for assignment in result.assignments {
            assignedStudent[assignment.shiftInstanceId] = studentByID[assignment.studentId]
        }

        return result.shiftInstances
            .filter { calendar.isDate($0.startDateTime, inSameDayAs: day) }
            .sorted { $0.startDateTime < $1.startDateTime }
            .map {
                CalendarShift(
                    id: $0.id,
                    shiftName: $0.name,
                    location: $0.location,
                    start: $0.startDateTime,
                    end: $0.endDateTime,
                    studentName: assignedStudent[$0.id]?.displayName ?? "Unassigned"
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
        let nextEnd = nextStart.addingTimeInterval(duration)

        result.shiftInstances[index].startDateTime = nextStart
        result.shiftInstances[index].endDateTime = nextEnd
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }
}

private struct DayCell: View {
    let day: Date
    let isCurrentMonth: Bool
    let shifts: [CalendarShift]
    let timezoneIdentifier: String
    let onDropShift: (String, Date) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption)
                .foregroundStyle(isCurrentMonth ? .primary : .secondary)

            ForEach(shifts) { shift in
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.studentName)
                        .font(.caption)
                        .lineLimit(1)
                    Text("\(shift.shiftName) • \(shift.location)")
                        .font(.caption2)
                        .lineLimit(1)
                    Text(timeLabel(start: shift.start, end: shift.end))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .draggable(shift.id)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minHeight: 124, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTarget ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

    private func timeLabel(start: Date, end: Date) -> String {
        var formatter = Date.FormatStyle(date: .omitted, time: .shortened)
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        return "\(start.formatted(formatter)) - \(end.formatted(formatter))"
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
    let location: String
    let start: Date
    let end: Date
    let studentName: String
}
