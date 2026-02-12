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
                    timezoneIdentifier: viewModel.project.rules.timezone,
                    rules: viewModel.project.rules,
                    shiftTemplates: viewModel.project.shiftTemplates,
                    shiftTypes: viewModel.project.shiftTypes
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
    private let weekdayOrder: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Block Window")
                            .font(.headline)
                        HStack(spacing: 16) {
                            blockField("Block Start Day") {
                                DatePicker("", selection: $viewModel.project.blockWindow.startDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            blockField("End Day") {
                                DatePicker("", selection: $viewModel.project.blockWindow.endDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Conference")
                            .font(.headline)
                        HStack(spacing: 16) {
                            blockField("Day") {
                                Picker("", selection: $viewModel.project.rules.conferenceDay) {
                                    ForEach(weekdayOrder) { day in
                                        Text(day.fullName).tag(day)
                                    }
                                }
                                .labelsHidden()
                                .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                            }
                            blockField("Start Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.rules.conferenceStartTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            blockField("End Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.rules.conferenceEndTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("General Rules")
                            .font(.headline)

                        HStack(spacing: 12) {
                            styledStepperRow(
                                title: "Time Off (hours)",
                                value: $viewModel.project.rules.timeOffHours,
                                in: 0...72
                            )
                            styledStepperRow(
                                title: "Required Number of Shifts",
                                value: $viewModel.project.rules.numShiftsRequired,
                                in: 0...100
                            )
                        }
                    }
                }

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

    @ViewBuilder
    private func blockField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .fontWeight(.medium)
            content()
        }
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func styledStepperRow(title: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Text("\(title):")
                .fontWeight(.medium)
                .frame(width: 170, alignment: .leading)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func localTimeBinding(_ localTime: Binding<LocalTime>) -> Binding<Date> {
        Binding(
            get: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let now = Date()
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = localTime.wrappedValue.hour
                components.minute = localTime.wrappedValue.minute
                components.second = 0
                return calendar.date(from: components) ?? now
            },
            set: { newValue in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone.current
                let components = calendar.dateComponents([.hour, .minute], from: newValue)
                localTime.wrappedValue = LocalTime(hour: components.hour ?? 0, minute: components.minute ?? 0)
            }
        )
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
