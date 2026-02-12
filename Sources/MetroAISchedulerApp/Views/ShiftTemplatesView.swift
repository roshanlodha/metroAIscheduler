import SwiftUI

struct ShiftTemplatesView: View {
    @Binding var project: ScheduleTemplateProject
    var onChanged: () -> Void
    @State private var selectedTemplateID: UUID?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Shift Templates")
                        .font(.title2)
                    Spacer()
                    Button("Add Template") {
                        let newTemplate = ShiftTemplate()
                        project.shiftTemplates.append(newTemplate)
                        selectedTemplateID = newTemplate.id
                        onChanged()
                    }
                }
                List(selection: $selectedTemplateID) {
                    ForEach(project.shiftTemplates) { template in
                        Text(template.name.isEmpty ? "Untitled Template" : template.name)
                            .tag(template.id)
                    }
                }
            }
            .frame(minWidth: 260, maxWidth: 320)

            Divider()

            if let templateBinding = selectedTemplateBinding {
                Form {
                    Section("Template Fields") {
                        TextField("Name", text: templateBinding.name)
                        TextField("Location", text: templateBinding.location)
                        Toggle("Overnight", isOn: templateBinding.isOvernight)
                        Toggle("Active", isOn: templateBinding.active)
                    }

                    Section("Shift Limits Per Student") {
                        TextField("Min shifts", value: templateBinding.minShifts, format: .number)
                        TextField("Max shifts", value: templateBinding.maxShifts, format: .number)
                    }

                    Section("Timing") {
                        Stepper(value: templateBinding.startTime.hour, in: 0...23) {
                            Text("Start hour: \(templateBinding.startTime.hour.wrappedValue)")
                        }
                        Stepper(value: templateBinding.startTime.minute, in: 0...59) {
                            Text("Start minute: \(templateBinding.startTime.minute.wrappedValue)")
                        }
                        TextField("Length hours (optional for overnight)", value: templateBinding.lengthHours, format: .number)
                    }

                    Section("Days Offered") {
                        WeekdayPicker(title: "", selected: templateBinding.daysOffered)
                    }

                    Button(role: .destructive) {
                        if let selectedTemplateID {
                            project.shiftTemplates.removeAll { $0.id == selectedTemplateID }
                            self.selectedTemplateID = project.shiftTemplates.first?.id
                        }
                        onChanged()
                    } label: {
                        Text("Delete Template")
                    }
                }
            } else {
                ContentUnavailableView("Select a template", systemImage: "clock.badge.questionmark")
            }
        }
        .padding()
        .onAppear {
            if selectedTemplateID == nil {
                selectedTemplateID = project.shiftTemplates.first?.id
            }
        }
        .onChange(of: project.shiftTemplates) { _, _ in
            onChanged()
            if let selectedTemplateID, !project.shiftTemplates.contains(where: { $0.id == selectedTemplateID }) {
                self.selectedTemplateID = project.shiftTemplates.first?.id
            }
        }
    }

    private func binding(for template: ShiftTemplate) -> Binding<ShiftTemplate> {
        guard let idx = project.shiftTemplates.firstIndex(where: { $0.id == template.id }) else {
            return .constant(template)
        }
        return $project.shiftTemplates[idx]
    }

    private var selectedTemplateBinding: Binding<ShiftTemplate>? {
        guard let selectedTemplateID,
              let template = project.shiftTemplates.first(where: { $0.id == selectedTemplateID }) else {
            return nil
        }
        return binding(for: template)
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
