import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
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
    }
}
