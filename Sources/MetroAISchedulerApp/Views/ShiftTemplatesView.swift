import SwiftUI

struct ShiftTemplatesView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedShiftID: UUID?
    @State private var selectedBundleID: UUID?
    @State private var newBundleName: String = ""

    var body: some View {
        HStack(spacing: 16) {
            templateLibraryPane
            Divider()
            activeShiftsPane
        }
        .padding()
        .onAppear {
            if selectedShiftID == nil {
                selectedShiftID = viewModel.project.shiftTemplates.first?.id
            }
            if selectedBundleID == nil {
                selectedBundleID = viewModel.project.templateLibrary.first?.id
            }
        }
        .onChange(of: viewModel.project.shiftTemplates) { _, _ in
            viewModel.validate()
            if let selectedShiftID, !viewModel.project.shiftTemplates.contains(where: { $0.id == selectedShiftID }) {
                self.selectedShiftID = viewModel.project.shiftTemplates.first?.id
            }
        }
    }

    private var templateLibraryPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Templates")
                .font(.title3)

            List(selection: $selectedBundleID) {
                ForEach(viewModel.project.templateLibrary) { bundle in
                    HStack {
                        Text(bundle.name)
                        Spacer()
                        Text("\(bundle.shifts.count) shifts")
                            .foregroundStyle(.secondary)
                    }
                    .tag(bundle.id)
                }
            }

            HStack {
                Button("Import Shift Schedule from Template") {
                    guard let bundle = selectedBundle else { return }
                    viewModel.loadShiftBundle(bundle)
                    selectedShiftID = viewModel.project.shiftTemplates.first?.id
                }
                .disabled(selectedBundle == nil)

                Button("Delete") {
                    guard let selectedBundleID else { return }
                    viewModel.project.templateLibrary.removeAll { $0.id == selectedBundleID }
                    self.selectedBundleID = viewModel.project.templateLibrary.first?.id
                }
                .disabled(selectedBundle == nil)
            }

            Divider()

            TextField("New template name", text: $newBundleName)
            Button("Save Shift Schedule as Template") {
                viewModel.saveCurrentShiftsAsTemplate(named: newBundleName)
                newBundleName = ""
                selectedBundleID = viewModel.project.templateLibrary.last?.id
            }
            .disabled(viewModel.project.shiftTemplates.isEmpty)

            Button("Load Metro Preset (Trauma/Overnight/Acute/West/Community/MLF)") {
                viewModel.loadMetroPresetIntoCurrentShifts()
                selectedShiftID = viewModel.project.shiftTemplates.first?.id
                selectedBundleID = viewModel.project.templateLibrary.first(where: { $0.name == "Metro ED (from solve.py)" })?.id
            }
        }
        .frame(minWidth: 350, maxWidth: 420)
    }

    private var activeShiftsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Template Shifts")
                    .font(.title3)
                Spacer()
                Button("Add Shift") {
                    let shift = ShiftTemplate(daysOffered: [.monday, .tuesday, .thursday, .friday, .saturday, .sunday])
                    viewModel.project.shiftTemplates.append(shift)
                    selectedShiftID = shift.id
                }
            }

            HStack(spacing: 16) {
                List(selection: $selectedShiftID) {
                    ForEach(viewModel.project.shiftTemplates) { shift in
                        VStack(alignment: .leading) {
                            Text(shift.name.isEmpty ? "Untitled Shift" : shift.name)
                            Text("\(shift.location) • \(shift.startTime.display)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(shift.id)
                    }
                }
                .frame(minWidth: 260, maxWidth: 320)

                if let shiftBinding = selectedShiftBinding {
                    Form {
                        Section("Shift") {
                            TextField("Name", text: shiftBinding.name)
                            TextField("Location", text: shiftBinding.location)
                            Toggle("Overnight", isOn: shiftBinding.isOvernight)
                            Toggle("Active", isOn: shiftBinding.active)
                        }

                        Section("Per Student Limits") {
                            TextField("Min shifts", value: shiftBinding.minShifts, format: .number)
                            TextField("Max shifts", value: shiftBinding.maxShifts, format: .number)
                        }

                        Section("Timing") {
                            Stepper(value: shiftBinding.startTime.hour, in: 0...23) {
                                Text("Start hour: \(shiftBinding.startTime.hour.wrappedValue)")
                            }
                            Stepper(value: shiftBinding.startTime.minute, in: 0...59) {
                                Text("Start minute: \(shiftBinding.startTime.minute.wrappedValue)")
                            }
                            TextField("Length hours (optional for overnight)", value: shiftBinding.lengthHours, format: .number)
                        }

                        Section("Days Offered") {
                            WeekdayPicker(title: "", selected: shiftBinding.daysOffered)
                        }

                        Button(role: .destructive) {
                            if let selectedShiftID {
                                viewModel.project.shiftTemplates.removeAll { $0.id == selectedShiftID }
                                self.selectedShiftID = viewModel.project.shiftTemplates.first?.id
                            }
                        } label: {
                            Text("Delete Shift")
                        }
                    }
                } else {
                    ContentUnavailableView("Select a shift", systemImage: "clock.badge.questionmark")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var selectedBundle: ShiftBundleTemplate? {
        guard let selectedBundleID else { return nil }
        return viewModel.project.templateLibrary.first(where: { $0.id == selectedBundleID })
    }

    private var selectedShiftBinding: Binding<ShiftTemplate>? {
        guard let selectedShiftID,
              let idx = viewModel.project.shiftTemplates.firstIndex(where: { $0.id == selectedShiftID }) else {
            return nil
        }
        return $viewModel.project.shiftTemplates[idx]
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
