import SwiftUI

struct StudentsView: View {
    @Binding var project: ScheduleTemplateProject

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Students")
                    .font(.title2)
                Spacer()
                Button("Add Student") {
                    project.students.append(Student())
                }
            }

            Table(project.students) {
                TableColumn("First") { student in
                    TextField("First", text: binding(for: student).firstName)
                }
                TableColumn("Last") { student in
                    TextField("Last", text: binding(for: student).lastName)
                }
                TableColumn("Email") { student in
                    TextField("Email", text: binding(for: student).email)
                }
                TableColumn("Delete") { student in
                    Button(role: .destructive) {
                        project.students.removeAll { $0.id == student.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .padding()
    }

    private func binding(for student: Student) -> Binding<Student> {
        guard let idx = project.students.firstIndex(where: { $0.id == student.id }) else {
            return .constant(student)
        }
        return $project.students[idx]
    }
}
