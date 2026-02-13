import SwiftUI

struct BlockRulesView: View {
    @Binding var project: ScheduleTemplateProject
    var onChanged: () -> Void
    private let weekdayOrder: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    private var projectTimeZone: TimeZone {
        TimeZone(identifier: project.rules.timezone) ?? .current
    }

    var body: some View {
        Form {
            Section("Block Window") {
                DatePicker("Start Date", selection: dateOnlyBinding($project.blockWindow.startDate), displayedComponents: .date)
                    .environment(\.timeZone, projectTimeZone)
                DatePicker("End Date", selection: dateOnlyBinding($project.blockWindow.endDate), displayedComponents: .date)
                    .environment(\.timeZone, projectTimeZone)
            }

            Section("Global Rules") {
                TextField("Timezone", text: $project.rules.timezone)
                Stepper(value: $project.rules.timeOffHours, in: 0...72) {
                    Text("Minimum rest hours: \(project.rules.timeOffHours)")
                }
                Stepper(value: $project.rules.numShiftsRequired, in: 0...100) {
                    Text("Required Number of Shifts: \(project.rules.numShiftsRequired)")
                }
                Stepper(value: $project.rules.solverTimeLimitSeconds, in: 1...300) {
                    Text("Solver time limit (sec): \(project.rules.solverTimeLimitSeconds)")
                }
                Toggle("No double booking", isOn: $project.rules.noDoubleBooking)
                Picker("Conference Day", selection: $project.rules.conferenceDay) {
                    ForEach(weekdayOrder) { day in
                        Text(day.fullName).tag(day)
                    }
                }
                DatePicker(
                    "Conference Start",
                    selection: localTimeBinding($project.rules.conferenceStartTime),
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Conference End",
                    selection: localTimeBinding($project.rules.conferenceEndTime),
                    displayedComponents: .hourAndMinute
                )
            }
        }
        .padding()
        .onChange(of: project) { _, _ in onChanged() }
    }

    private func localTimeBinding(_ localTime: Binding<LocalTime>) -> Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let now = Date()
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = localTime.wrappedValue.hour
                components.minute = localTime.wrappedValue.minute
                components.second = 0
                return calendar.date(from: components) ?? now
            },
            set: { newValue in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                localTime.wrappedValue = LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
    }

    private func dateOnlyBinding(_ date: Binding<Date>) -> Binding<Date> {
        Binding(
            get: {
                normalizedDateOnly(date.wrappedValue)
            },
            set: { newValue in
                date.wrappedValue = normalizedDateOnly(newValue)
            }
        )
    }

    private func normalizedDateOnly(_ value: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = projectTimeZone
        var components = calendar.dateComponents([.year, .month, .day], from: value)
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = projectTimeZone
        return calendar.date(from: components) ?? value
    }
}
