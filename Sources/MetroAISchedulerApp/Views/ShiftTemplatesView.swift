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
                            Text("\(shift.location) • \(shift.startTime.display)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(shift.id)
                    }
                }
                .frame(minHeight: 200)
            } label: {
                Text("Shift List")
            }

            GroupBox {
                if let shiftBinding = selectedShiftBinding {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Shift Parameters")
                                .font(.headline)

                            TextField("Name", text: shiftBinding.name)
                            TextField("Location", text: shiftBinding.location)

                            HStack(spacing: 16) {
                                Toggle("Overnight", isOn: shiftBinding.isOvernight)
                                Toggle("Active", isOn: shiftBinding.active)
                            }

                            Divider()

                            Text("Per Student Limits")
                                .font(.subheadline)
                            HStack(spacing: 12) {
                                TextField("Min shifts", value: shiftBinding.minShifts, format: .number)
                                TextField("Max shifts", value: shiftBinding.maxShifts, format: .number)
                            }

                            Divider()

                            Text("Timing")
                                .font(.subheadline)
                            Stepper(value: shiftBinding.startTime.hour, in: 0...23) {
                                Text("Start hour: \(shiftBinding.startTime.hour.wrappedValue)")
                            }
                            Stepper(value: shiftBinding.startTime.minute, in: 0...59) {
                                Text("Start minute: \(shiftBinding.startTime.minute.wrappedValue)")
                            }
                            TextField("Length hours (optional for overnight)", value: shiftBinding.lengthHours, format: .number)

                            Divider()

                            Text("Days Offered")
                                .font(.subheadline)
                            WeekdayPicker(title: "", selected: shiftBinding.daysOffered)

                            Button(role: .destructive) {
                                deleteSelectedShift()
                            } label: {
                                Text("Delete Shift")
                            }
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
        let shift = ShiftTemplate(daysOffered: [.monday, .tuesday, .thursday, .friday, .saturday, .sunday])
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
