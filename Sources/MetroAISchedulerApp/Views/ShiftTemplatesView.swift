import SwiftUI

struct ShiftTemplatesView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedShiftID: UUID?

    private let dayOrder: [Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GroupBox {
                VStack(spacing: 8) {
                    ForEach($viewModel.project.shiftTypes) { $type in
                        HStack(spacing: 10) {
                            TextField("Type name", text: $type.name)
                                .frame(minWidth: 130)
                            optionalStepperInline(title: "Min", value: $type.minShifts, range: 0...40)
                            optionalStepperInline(title: "Max", value: $type.maxShifts, range: 0...80)
                            Button(role: .destructive) {
                                deleteType(type.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(isTypeUsed(type.id))
                        }
                    }

                    HStack {
                        Spacer()
                        Button("Add Shift Type") {
                            viewModel.project.shiftTypes.append(ShiftType(name: "New Type"))
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Text("Shift Types")
            }

            GroupBox {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($viewModel.project.shiftTemplates) { $shift in
                            shiftRow(shift: $shift)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            } label: {
                Text("Shift List")
            }
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

    private func shiftRow(shift: Binding<ShiftTemplate>) -> some View {
        let isSelected = selectedShiftID == shift.wrappedValue.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shift.wrappedValue.name.isEmpty ? "Untitled Shift" : shift.wrappedValue.name)
                        .font(.headline)
                    Text("\(shift.wrappedValue.location) • \(displayTimeRange(shift: shift.wrappedValue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(typeName(for: shift.wrappedValue.shiftTypeId))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                Button(role: .destructive) {
                    deleteShift(id: shift.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 5) {
                ForEach(dayOrder) { day in
                    Toggle(day.shortName.prefix(2), isOn: Binding(
                        get: { shift.wrappedValue.daysOffered.contains(day) },
                        set: { include in
                            if include {
                                shift.wrappedValue.daysOffered.insert(day)
                            } else {
                                shift.wrappedValue.daysOffered.remove(day)
                            }
                        }
                    ))
                    .toggleStyle(.button)
                    .font(.caption2)
                }
            }

            if isSelected {
                Divider()
                shiftInlineEditor(shift: shift)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.14)) {
                selectedShiftID = (selectedShiftID == shift.wrappedValue.id) ? nil : shift.wrappedValue.id
            }
        }
    }

    @ViewBuilder
    private func shiftInlineEditor(shift: Binding<ShiftTemplate>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shift Parameters")
                .font(.subheadline.weight(.semibold))

            labeledRow("Name") {
                TextField("Shift name", text: shift.name)
            }

            labeledRow("Location") {
                TextField("Location", text: shift.location)
            }

            labeledRow("Type") {
                Picker("", selection: Binding<UUID?>(
                    get: { shift.wrappedValue.shiftTypeId },
                    set: { shift.wrappedValue.shiftTypeId = $0 }
                )) {
                    Text("Unassigned").tag(UUID?.none)
                    ForEach(viewModel.project.shiftTypes) { type in
                        Text(type.name).tag(UUID?.some(type.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            labeledRow("Overnight") {
                Toggle("", isOn: shift.isOvernight)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                labeledRow("Start") {
                    DatePicker("", selection: dateBinding(for: shift.startTime), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                labeledRow("End") {
                    DatePicker("", selection: dateBinding(for: shift.endTime, fallback: shift.startTime.wrappedValue), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        }
    }

    private func addShift() {
        let shift = ShiftTemplate(
            minShifts: nil,
            maxShifts: nil,
            shiftTypeId: viewModel.project.shiftTypes.first?.id,
            startTime: LocalTime(hour: 7, minute: 0),
            endTime: LocalTime(hour: 15, minute: 0),
            daysOffered: [.monday, .tuesday, .thursday, .friday, .saturday, .sunday],
            active: true
        )
        viewModel.project.shiftTemplates.append(shift)
        selectedShiftID = shift.id
    }

    private func deleteShift(id: UUID) {
        viewModel.project.shiftTemplates.removeAll { $0.id == id }
        if selectedShiftID == id {
            selectedShiftID = viewModel.project.shiftTemplates.first?.id
        }
    }

    private func deleteType(_ id: UUID) {
        guard !isTypeUsed(id) else { return }
        viewModel.project.shiftTypes.removeAll { $0.id == id }
    }

    private func isTypeUsed(_ id: UUID) -> Bool {
        viewModel.project.shiftTemplates.contains(where: { $0.shiftTypeId == id })
    }

    private func typeName(for id: UUID?) -> String {
        guard let id, let type = viewModel.project.shiftTypes.first(where: { $0.id == id }) else {
            return "Unassigned"
        }
        return type.name
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
    private func optionalStepperInline(title: String, value: Binding<Int?>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 5) {
            Text("\(title):")
                .font(.caption)
            Button {
                if let current = value.wrappedValue {
                    let next = current - 1
                    value.wrappedValue = next >= range.lowerBound ? next : nil
                }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(value.wrappedValue == nil)

            Text(value.wrappedValue.map(String.init) ?? "None")
                .font(.caption)
                .monospacedDigit()
                .frame(minWidth: 30)

            Button {
                let current = value.wrappedValue ?? (range.lowerBound - 1)
                value.wrappedValue = min(range.upperBound, current + 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .underPageBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
