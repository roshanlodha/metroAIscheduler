import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showCalendarPage = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BentoCard {
                    ShiftTemplatesView(viewModel: viewModel)
                }
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 12) {
                    BentoCard {
                        StudentsView(project: $viewModel.project)
                    }
                    .frame(minHeight: 280)

                    BentoCard {
                        ActionsAndRulesPane(viewModel: viewModel)
                    }
                    .frame(minHeight: 360)
                }
                .frame(minWidth: 480, idealWidth: 540, maxWidth: 620, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(12)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                TextField("Project Name", text: $viewModel.project.name)
                    .frame(width: 240)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Load Project") { loadProject() }
                Button("Save Project") { saveProject() }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: viewModel.result) { _, newValue in
            if newValue != nil {
                showCalendarPage = true
            }
        }
        .sheet(isPresented: $showCalendarPage) {
            if let resultBinding {
                MonthlyCalendarPage(
                    result: resultBinding,
                    students: viewModel.project.students,
                    timezoneIdentifier: viewModel.project.rules.timezone
                )
            }
        }
    }

    private var resultBinding: Binding<ScheduleResult>? {
        guard viewModel.result != nil else { return nil }
        return Binding(
            get: { viewModel.result! },
            set: { viewModel.result = $0 }
        )
    }

    private func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadProject(from: url)
        }
    }

    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "metro-project.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveProject(to: url)
        }
    }
}

private struct ActionsAndRulesPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: viewModel.createSchedule) {
                        if viewModel.isSolving {
                            ProgressView()
                        } else {
                            Text("Generate Schedule")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSolving)

                    Spacer()

                    if viewModel.result != nil {
                        Button("Export JSON") { exportJSON() }
                        Button("Export CSV") { exportCSV() }
                    }
                }

                GroupBox("Block Window") {
                    DatePicker("Start Date", selection: $viewModel.project.blockWindow.startDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $viewModel.project.blockWindow.endDate, displayedComponents: .date)
                }

                GroupBox("General Rules") {
                    Stepper(value: $viewModel.project.rules.timeOffHours, in: 0...72) {
                        Text("Minimum rest hours: \(viewModel.project.rules.timeOffHours)")
                    }
                    Stepper(value: $viewModel.project.rules.numShiftsRequired, in: 0...100) {
                        Text("Required total shift score per student: \(viewModel.project.rules.numShiftsRequired)")
                    }
                    Stepper(value: $viewModel.project.rules.overnightShiftWeight, in: 1...10) {
                        Text("Overnight shift weight: \(viewModel.project.rules.overnightShiftWeight)")
                    }
                    Toggle("No double booking", isOn: $viewModel.project.rules.noDoubleBooking)
                    Toggle("Allow overnight before Wednesday", isOn: $viewModel.project.rules.allowOvernightBeforeWednesday)
                }

                if !viewModel.validationIssues.isEmpty {
                    GroupBox("Validation") {
                        ForEach(viewModel.validationIssues) { issue in
                            Text("• \(issue.message)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if let diagnostic = viewModel.solverDiagnostic {
                    GroupBox("Solver Diagnostics") {
                        Text(diagnostic.message)
                            .font(.headline)
                        ForEach(diagnostic.details, id: \.self) { detail in
                            Text("• \(detail)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: viewModel.project) { _, _ in
            viewModel.validate()
        }
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
}

private struct BentoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
