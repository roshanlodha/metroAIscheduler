import SwiftUI

struct StudentsView: View {
    @Binding var project: ScheduleTemplateProject

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Students")
                .font(.title3)

            headerRow

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(project.students) { student in
                        studentRow(for: student)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .onAppear {
            ensureTrailingEmptyRow()
        }
        .onChange(of: project.students) { _, _ in
            ensureTrailingEmptyRow()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Name")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Email")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
                .frame(width: 24)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func studentRow(for student: Student) -> some View {
        let rowBinding = binding(for: student)
        HStack(spacing: 10) {
            TextField("Name", text: rowBinding.name)
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: rowBinding.email)
                .textFieldStyle(.roundedBorder)

            if !isEmpty(student) {
                Button(role: .destructive) {
                    project.students.removeAll { $0.id == student.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            } else {
                Spacer()
                    .frame(width: 24)
            }
        }
        .padding(.horizontal, 6)
    }

    private func binding(for student: Student) -> Binding<Student> {
        guard let idx = project.students.firstIndex(where: { $0.id == student.id }) else {
            return .constant(student)
        }
        return $project.students[idx]
    }

    private func ensureTrailingEmptyRow() {
        let nonEmpty = project.students.filter { !isEmpty($0) }
        let trailingEmpty = project.students.last.flatMap { isEmpty($0) ? $0 : nil } ?? Student()
        let desired = nonEmpty + [trailingEmpty]

        if desired != project.students {
            project.students = desired
        }
    }

    private func isEmpty(_ student: Student) -> Bool {
        student.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        student.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
