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
            seedDefaultStudentsIfNeeded()
            ensureTrailingEmptyRow()
        }
        .onChange(of: project.students) { _, _ in
            ensureTrailingEmptyRow()
        }
        .onChange(of: project.defaultStudentCount) { oldValue, newValue in
            guard newValue != oldValue else { return }
            seedDefaultStudentsIfNeeded()
            ensureTrailingEmptyRow()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("First")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Last")
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
            TextField("First", text: rowBinding.firstName)
                .textFieldStyle(.roundedBorder)
            TextField("Last", text: rowBinding.lastName)
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

    private func seedDefaultStudentsIfNeeded() {
        let nonEmpty = project.students.filter { !isEmpty($0) }
        guard nonEmpty.isEmpty, project.students.count <= 1, project.defaultStudentCount > 0 else {
            return
        }

        let seeded = (1...project.defaultStudentCount).map { index in
            Student(firstName: "Student \(index)")
        }
        project.students = seeded + [Student()]
    }

    private func isEmpty(_ student: Student) -> Bool {
        student.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        student.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        student.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
