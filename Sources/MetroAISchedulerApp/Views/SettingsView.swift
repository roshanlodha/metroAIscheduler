import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    private let weekdayOrder: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        Form {
            Section("Block Window") {
                Picker("Block Start Day", selection: $viewModel.project.rules.blockStartDay) {
                    ForEach(weekdayOrder) { day in
                        Text(day.fullName).tag(day)
                    }
                }
            }

            Section("Student Defaults") {
                Stepper(value: $viewModel.project.defaultStudentCount, in: 0...200) {
                    Text("Default number of students: \(viewModel.project.defaultStudentCount)")
                }
            }

            Section("Locked Block Rules") {
                TextField("Timezone", text: $viewModel.project.rules.timezone)

                Stepper(value: $viewModel.project.rules.solverTimeLimitSeconds, in: 1...300) {
                    Text("Solver time limit (sec): \(viewModel.project.rules.solverTimeLimitSeconds)")
                }

                Toggle("No double booking", isOn: $viewModel.project.rules.noDoubleBooking)
            }

            Section {
                Text("These settings are separated from the main workflow to keep schedule editing cleaner.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onChange(of: viewModel.project.rules.timezone) { _, _ in
            viewModel.validate()
        }
        .onChange(of: viewModel.project.rules.solverTimeLimitSeconds) { _, _ in
            viewModel.validate()
        }
        .onChange(of: viewModel.project.rules.noDoubleBooking) { _, _ in
            viewModel.validate()
        }
        .onChange(of: viewModel.project.defaultStudentCount) { _, _ in
            viewModel.validate()
        }
        .onChange(of: viewModel.project.rules.blockStartDay) { _, _ in
            alignBlockWindowToStartDay()
            viewModel.validate()
        }
    }

    private func alignBlockWindowToStartDay() {
        let timezone = TimeZone(identifier: viewModel.project.rules.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        calendar.firstWeekday = 2

        let currentStart = viewModel.project.blockWindow.startDate
        let currentEnd = viewModel.project.blockWindow.endDate
        let spanDays = max(0, calendar.dateComponents([.day], from: currentStart, to: currentEnd).day ?? 0)

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: currentStart)?.start ?? calendar.startOfDay(for: currentStart)
        let offset = weekdayOffset(viewModel.project.rules.blockStartDay)
        let newStart = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
        let newEnd = calendar.date(byAdding: .day, value: spanDays, to: newStart) ?? newStart

        viewModel.project.blockWindow.startDate = newStart
        viewModel.project.blockWindow.endDate = newEnd
    }

    private func weekdayOffset(_ weekday: Weekday) -> Int {
        switch weekday {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }
}
