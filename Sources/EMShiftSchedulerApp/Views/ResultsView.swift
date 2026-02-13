import SwiftUI

struct ResultsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Results")
                .font(.title2)

            if let result = viewModel.result {
                HStack {
                    Button("Export JSON") { exportJSON() }
                    Button("Export CSV") { exportCSV() }
                    Spacer()
                }
                .padding(.bottom, 8)

                List {
                    ForEach(viewModel.project.students) { student in
                        Section(student.displayName) {
                            ForEach(assignments(for: student, result: result), id: \.id) { shift in
                                VStack(alignment: .leading) {
                                    Text("\(shift.name) @ \(shift.location)")
                                    Text("\(shift.startDateTime.formatted()) - \(shift.endDateTime.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("Export \(student.firstName) ICS") {
                                exportICS(for: student)
                            }
                        }
                    }
                }

                WeekCalendarView(result: result, students: viewModel.project.students)
                    .frame(height: 220)
            } else {
                Text("No generated schedule yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func assignments(for student: Student, result: ScheduleResult) -> [GeneratedShiftInstance] {
        let ids = Set(result.assignments.filter { $0.studentId == student.id }.map { $0.shiftInstanceId })
        return result.shiftInstances.filter { ids.contains($0.id) }.sorted { $0.startDateTime < $1.startDateTime }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "schedule-result.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveResultJSON(to: url)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "schedule.csv"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveCSV(to: url)
        }
    }

    private func exportICS(for student: Student) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.calendarEvent]
        panel.nameFieldStringValue = "\(student.firstName)-schedule.ics"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveICS(for: student, to: url)
        }
    }
}

private struct WeekCalendarView: View {
    let result: ScheduleResult
    let students: [Student]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated).month().day()))
                            .font(.headline)
                        ForEach(result.shiftInstances.filter { Calendar.current.isDate($0.startDateTime, inSameDayAs: day) }) { shift in
                            Text(shift.name)
                                .font(.caption)
                                .padding(4)
                                .background(Color.blue.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    .frame(width: 140, alignment: .topLeading)
                }
            }
        }
    }

    private var days: [Date] {
        let cal = Calendar.current
        guard let minDate = result.shiftInstances.map(\.startDateTime).min() else { return [] }
        let start = cal.startOfDay(for: minDate)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }
}
