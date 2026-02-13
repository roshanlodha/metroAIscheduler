import SwiftUI

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
                let color = template.shiftTypeId
                    .flatMap { shiftTypeByID[$0] }
                    .map { $0.color.swatchColor }
                    ?? .gray
                return ShiftRow(template: template, typeName: typeName, color: color)
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
                if let cell = cellData(for: row, day: day) {
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
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: dayWidth, height: rowHeight)
                        .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
            }
        }
    }

    private func cellData(for row: ShiftRow, day: Date) -> GridCellData? {
        guard let instance = result.shiftInstances.first(where: {
            $0.templateId == row.template.id && calendar.isDate($0.startDateTime, inSameDayAs: day)
        }) else {
            return nil
        }
        guard let assignment = assignmentByShiftID[instance.id] else {
            return nil
        }
        let student = studentByID[assignment.studentId]
        let studentName = (student?.displayName.isEmpty == false ? student?.displayName : student?.email) ?? "Unassigned"
        return GridCellData(
            studentName: studentName,
            timeLabel: shortTimeRange(start: instance.startDateTime, end: instance.endDateTime),
            color: row.color
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
    let color: Color

    var id: UUID { template.id }
}

private struct GridCellData {
    let studentName: String
    let timeLabel: String
    let color: Color
}
