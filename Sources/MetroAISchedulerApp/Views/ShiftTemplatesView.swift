import SwiftUI

struct ShiftTemplatesView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedShiftID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GroupBox {
                List(selection: $selectedShiftID) {
                    ForEach(viewModel.project.shiftTemplates) { shift in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.name.isEmpty ? "Untitled Shift" : shift.name)
                            Text("\(shift.location) • \(displayTimeRange(shift: shift))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(shift.id)
                    }
                }
                .frame(minHeight: 220)
            } label: {
                Text("Shift List")
            }

            GroupBox {
                if let shiftBinding = selectedShiftBinding {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Shift Parameters")
                                .font(.headline)

                            labeledRow("Name") {
                                TextField("Shift name", text: shiftBinding.name)
                                Button(role: .destructive) {
                                    deleteSelectedShift()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            labeledRow("Location") {
                                TextField("Location", text: shiftBinding.location)
                            }

                            labeledRow("Overnight") {
                                Toggle("", isOn: shiftBinding.isOvernight)
                                    .labelsHidden()
                            }

                            Divider()

                            Text("Per Student Limits")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                labeledStepperRow(
                                    title: "Min shifts",
                                    value: intBinding(shiftBinding.minShifts, fallback: 1),
                                    range: 1...40
                                )
                                labeledStepperRow(
                                    title: "Max shifts",
                                    value: intBinding(shiftBinding.maxShifts, fallback: max(1, shiftBinding.minShifts.wrappedValue ?? 1)),
                                    range: max(1, shiftBinding.minShifts.wrappedValue ?? 1)...80
                                )
                            }

                            Divider()

                            Text("Timing")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                labeledRow("Start") {
                                    DatePicker(
                                        "",
                                        selection: dateBinding(for: shiftBinding.startTime),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }
                                labeledRow("End") {
                                    DatePicker(
                                        "",
                                        selection: dateBinding(for: shiftBinding.endTime, fallback: shiftBinding.startTime.wrappedValue),
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }
                            }

                            Divider()

                            Text("Days Offered")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WeekdayPicker(title: "", selected: shiftBinding.daysOffered)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ContentUnavailableView("Select a shift", systemImage: "clock.badge.questionmark")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            } label: {
                Text("Edit Shift")
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .onAppear {
            if selectedShiftID == nil {
                selectedShiftID = viewModel.project.shiftTemplates.first?.id
            }
        }
        .onChange(of: viewModel.project.shiftTemplates) { _, _ in
            viewModel.validate()
            if let selectedShiftID, !viewModel.project.shiftTemplates.contains(where: { $0.id == selectedShiftID }) {
                self.selectedShiftID = viewModel.project.shiftTemplates.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Active Shift Template")
                .font(.title3)
            Spacer()
            Button("Import Schedule") { importSchedule() }
            Button("Export Schedule") { exportSchedule() }
            Button("Add Shift") { addShift() }
        }
    }

    private var selectedShiftBinding: Binding<ShiftTemplate>? {
        guard let selectedShiftID,
              let idx = viewModel.project.shiftTemplates.firstIndex(where: { $0.id == selectedShiftID }) else {
            return nil
        }
        return $viewModel.project.shiftTemplates[idx]
    }

    private func addShift() {
        let shift = ShiftTemplate(
            minShifts: 1,
            maxShifts: 1,
            startTime: LocalTime(hour: 7, minute: 0),
            endTime: LocalTime(hour: 15, minute: 0),
            daysOffered: [.monday, .tuesday, .thursday, .friday, .saturday, .sunday],
            active: true
        )
        viewModel.project.shiftTemplates.append(shift)
        selectedShiftID = shift.id
    }

    private func deleteSelectedShift() {
        guard let selectedShiftID else { return }
        viewModel.project.shiftTemplates.removeAll { $0.id == selectedShiftID }
        self.selectedShiftID = viewModel.project.shiftTemplates.first?.id
    }

    private func importSchedule() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.importShiftSchedule(from: url)
            selectedShiftID = viewModel.project.shiftTemplates.first?.id
        }
    }

    private func exportSchedule() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "shift-schedule-template.json"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportShiftSchedule(to: url)
        }
    }

    private func intBinding(_ source: Binding<Int?>, fallback: Int) -> Binding<Int> {
        Binding<Int>(
            get: { source.wrappedValue ?? fallback },
            set: { source.wrappedValue = $0 }
        )
    }

    private func dateBinding(for source: Binding<LocalTime?>, fallback: LocalTime) -> Binding<Date> {
        Binding<Date>(
            get: { localTimeToDate(source.wrappedValue ?? fallback) },
            set: { source.wrappedValue = dateToLocalTime($0) }
        )
    }

    private func dateBinding(for source: Binding<LocalTime>) -> Binding<Date> {
        Binding<Date>(
            get: { localTimeToDate(source.wrappedValue) },
            set: { source.wrappedValue = dateToLocalTime($0) }
        )
    }

    private func localTimeToDate(_ value: LocalTime) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = value.hour
        components.minute = value.minute
        return calendar.date(from: components) ?? now
    }

    private func dateToLocalTime(_ date: Date) -> LocalTime {
        let calendar = Calendar(identifier: .gregorian)
        return LocalTime(
            hour: calendar.component(.hour, from: date),
            minute: calendar.component(.minute, from: date)
        )
    }

    private func displayTimeRange(shift: ShiftTemplate) -> String {
        let start = localTimeToDate(shift.startTime).formatted(date: .omitted, time: .shortened)
        let endLocal = shift.endTime ?? shift.startTime
        let end = localTimeToDate(endLocal).formatted(date: .omitted, time: .shortened)
        return "\(start)-\(end)"
    }

    @ViewBuilder
    private func labeledRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(title):")
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)
            content()
        }
    }

    @ViewBuilder
    private func labeledStepperRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 10) {
            Text("\(title):")
                .fontWeight(.medium)
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WeekdayPicker: View {
    let title: String
    @Binding var selected: Set<Weekday>

    var body: some View {
        HStack {
            if !title.isEmpty {
                Text(title)
            }
            ForEach(Weekday.allCases) { day in
                Toggle(day.shortName, isOn: Binding(
                    get: { selected.contains(day) },
                    set: { include in
                        if include {
                            selected.insert(day)
                        } else {
                            selected.remove(day)
                        }
                    }
                ))
                .toggleStyle(.button)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
