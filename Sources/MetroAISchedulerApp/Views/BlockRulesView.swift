import SwiftUI

struct BlockRulesView: View {
    @Binding var project: ScheduleTemplateProject
    var onChanged: () -> Void
    private let weekdayOrder: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    var body: some View {
        Form {
            Section("Block Window") {
                DatePicker("Start Date", selection: $project.blockWindow.startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $project.blockWindow.endDate, displayedComponents: .date)
            }

            Section("Global Rules") {
                TextField("Timezone", text: $project.rules.timezone)
                Stepper(value: $project.rules.timeOffHours, in: 0...72) {
                    Text("Minimum rest hours: \(project.rules.timeOffHours)")
                }
                Stepper(value: $project.rules.numShiftsRequired, in: 0...100) {
                    Text("Required total shift score per student: \(project.rules.numShiftsRequired)")
                }
                Stepper(value: $project.rules.overnightShiftWeight, in: 1...10) {
                    Text("Overnight shift weight: \(project.rules.overnightShiftWeight)")
                }
                Stepper(value: $project.rules.overnightBlockCount, in: 1...7) {
                    Text("Overnight block days: \(project.rules.overnightBlockCount)")
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
            }
        }
        .padding()
        .onChange(of: project) { _, _ in onChanged() }
    }
}
