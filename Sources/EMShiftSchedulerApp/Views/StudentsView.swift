import SwiftUI

struct StudentsView: View {
    @Binding var project: ScheduleTemplateProject
    private let actionColumnWidth: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Students")
                .font(.title3)

            VStack(spacing: 0) {
                headerRow
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(project.students.enumerated()), id: \.element.id) { index, student in
                            studentRow(for: student, index: index)
                            if index < project.students.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(maxHeight: .infinity, alignment: .top)
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
        HStack(spacing: 0) {
            Text("Name")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            Divider()
            Text("Email")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            Divider()
            Text("")
                .frame(width: actionColumnWidth)
        }
        .frame(height: 32)
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.05))
    }

    @ViewBuilder
    private func studentRow(for student: Student, index: Int) -> some View {
        let rowBinding = binding(for: student)
        HStack(spacing: 0) {
            TextField("Example Student", text: rowBinding.name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Divider()
            TextField("student@example.com", text: rowBinding.email)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            Divider()

            if !isEmpty(student) {
                Button(role: .destructive) {
                    project.students.removeAll { $0.id == student.id }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: actionColumnWidth)
                }
                .buttonStyle(.borderless)
            } else {
                Color.clear
                    .frame(width: actionColumnWidth, height: 30)
            }
        }
        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.045))
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
