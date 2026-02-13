import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showCalendarPage = false

    var body: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    BentoCard {
                        ShiftTemplatesView(viewModel: viewModel)
                    }
                    .frame(minWidth: 500, idealWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

                    rightColumn
                        .frame(minWidth: 420, idealWidth: 540, maxWidth: 620, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                ScrollView {
                    VStack(spacing: 12) {
                        BentoCard {
                            ShiftTemplatesView(viewModel: viewModel)
                        }
                        .frame(minHeight: 420)

                        rightColumn
                    }
                }
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                    if let statusDetailText {
                        Text(statusDetailText)
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
                    shiftTypes: viewModel.project.shiftTypes,
                    onExportJSON: exportResultJSON,
                    onExportCSV: exportResultCSV,
                    onExportAllICS: exportAllICS
                )
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 12) {
            BentoCard {
                StudentsView(project: $viewModel.project)
            }
            .frame(minHeight: 220, idealHeight: 280, maxHeight: .infinity)

            BentoCard {
                ActionsAndRulesPane(viewModel: viewModel)
            }
            .frame(minHeight: 300, idealHeight: 380, maxHeight: .infinity)
        }
    }

    private var statusDetailText: String? {
        if let diagnostic = viewModel.solverDiagnostic {
            let details = ([diagnostic.message] + diagnostic.details)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return details.isEmpty ? nil : details.joined(separator: " • ")
        }
        let issueMessages = viewModel.validationIssues.map(\.message)
        return issueMessages.isEmpty ? nil : issueMessages.joined(separator: " • ")
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
        panel.nameFieldStringValue = "template.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveProject(to: url)
        }
    }

    private func exportAllICS() {
        guard viewModel.result != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]
        panel.nameFieldStringValue = "schedules.zip"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveAllICSArchive(to: url)
        }
    }

    private func exportResultJSON() {
        guard viewModel.result != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "schedule-result.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveResultJSON(to: url)
        }
    }

    private func exportResultCSV() {
        guard viewModel.result != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "schedule.csv"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.saveCSV(to: url)
        }
    }
}

private struct ActionsAndRulesPane: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isAdvancedExpanded = false
    private let weekdayOrder: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    private var projectTimeZone: TimeZone {
        TimeZone(identifier: viewModel.project.rules.timezone) ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    formSection("Block Settings") {
                        HStack(spacing: 16) {
                            inlineField("Start Date") {
                                DatePicker("", selection: dateOnlyBinding($viewModel.project.blockWindow.startDate), displayedComponents: .date)
                                    .environment(\.timeZone, projectTimeZone)
                                    .labelsHidden()
                            }
                            inlineField("End Date") {
                                DatePicker("", selection: dateOnlyBinding($viewModel.project.blockWindow.endDate), displayedComponents: .date)
                                    .environment(\.timeZone, projectTimeZone)
                                    .labelsHidden()
                            }
                        }
                    }

                    formSection("Orientation") {
                        HStack(spacing: 16) {
                            inlineField("Date") {
                                DatePicker("", selection: dateOnlyBinding($viewModel.project.orientation.startDate), displayedComponents: .date)
                                    .environment(\.timeZone, projectTimeZone)
                                    .labelsHidden()
                            }
                            inlineField("Start Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.orientation.startTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            inlineField("End Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.orientation.endTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                        }
                    }

                    formSection("Conference") {
                        HStack(spacing: 16) {
                            inlineField("Day") {
                                Picker("", selection: $viewModel.project.rules.conferenceDay) {
                                    ForEach(weekdayOrder) { day in
                                        Text(day.fullName).tag(day)
                                    }
                                }
                                .labelsHidden()
                                .frame(minWidth: 120, alignment: .leading)
                            }
                            inlineField("Start Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.rules.conferenceStartTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                            inlineField("End Time") {
                                DatePicker(
                                    "",
                                    selection: localTimeBinding($viewModel.project.rules.conferenceEndTime),
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                            }
                        }
                    }

                    formSection("Requirements") {
                        HStack(spacing: 16) {
                            inlineStepperField(
                                title: "Time Off (hrs)",
                                value: $viewModel.project.rules.timeOffHours,
                                in: 0...72
                            )
                            inlineStepperField(
                                title: "Required Shift Count",
                                value: $viewModel.project.rules.numShiftsRequired,
                                in: 0...100
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                            HStack(spacing: 16) {
                                inlineStepperField(
                                    title: "Solver Time (s)",
                                    value: $viewModel.project.rules.solverTimeLimitSeconds,
                                    in: 1...300
                                )
                                inlineToggleField(title: "Double Booking", isOn: doubleBookingBinding)
                            }
                            .padding(.top, 6)
                        } label: {
                            sectionTitle("Advanced Settings")
                        }

                        Divider()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Button(action: viewModel.createSchedule) {
                if viewModel.isSolving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Generate Schedule")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .help("Generate schedule")
            .disabled(viewModel.isSolving)

        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.project) { _, _ in
            viewModel.validate()
        }
    }

    @ViewBuilder
    private func inlineField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 76, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.top, 1)
    }

    @ViewBuilder
    private func inlineStepperField(title: String, value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 108, alignment: .leading)
            Text("\(value.wrappedValue)")
                .monospacedDigit()
                .font(.headline.weight(.semibold))
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    @ViewBuilder
    private func inlineToggleField(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 108, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    @ViewBuilder
    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
            Divider()
        }
    }

    private var doubleBookingBinding: Binding<Bool> {
        Binding(
            get: { !viewModel.project.rules.noDoubleBooking },
            set: { viewModel.project.rules.noDoubleBooking = !$0 }
        )
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

private struct BentoCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
