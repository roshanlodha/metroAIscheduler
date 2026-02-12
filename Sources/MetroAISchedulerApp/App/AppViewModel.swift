import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var project: ScheduleTemplateProject
    @Published var result: ScheduleResult?
    @Published var validationIssues: [ValidationIssue] = []
    @Published var statusMessage: String = "Ready"
    @Published var solverDiagnostic: SolverDiagnostic?
    @Published var isSolving: Bool = false

    private let solver: SolverAdapter

    init(solver: SolverAdapter = PythonSolverAdapter()) {
        self.project = ScheduleTemplateProject.sample()
        self.solver = solver
        validate()
    }

    func validate() {
        validationIssues = ProjectValidator.validate(project: project)
    }

    func createSchedule() {
        validate()
        guard validationIssues.isEmpty else {
            statusMessage = "Fix validation issues before solving."
            return
        }

        let instances = ShiftExpansion.expand(project: project)
        let projectSnapshot = project
        let solverRef = solver
        isSolving = true
        statusMessage = "Generating schedule..."
        solverDiagnostic = nil

        Task.detached {
            do {
                let solved = try solverRef.solve(project: projectSnapshot, shiftInstances: instances)
                await MainActor.run {
                    self.result = solved
                    self.statusMessage = "Schedule generated with \(solved.assignments.count) assignments."
                    self.isSolving = false
                }
            } catch let error as SolverError {
                await MainActor.run {
                    switch error {
                    case .infeasible(let diagnostic):
                        self.solverDiagnostic = diagnostic
                    default:
                        self.solverDiagnostic = SolverDiagnostic(message: "Solve failed", details: [error.localizedDescription])
                    }
                    self.statusMessage = "Failed to generate schedule."
                    self.isSolving = false
                }
            } catch {
                await MainActor.run {
                    self.solverDiagnostic = SolverDiagnostic(message: "Unexpected error", details: [error.localizedDescription])
                    self.statusMessage = "Failed to generate schedule."
                    self.isSolving = false
                }
            }
        }
    }

    func loadProject(from url: URL) {
        do {
            project = try ProjectStore.loadProject(from: url)
            result = nil
            statusMessage = "Loaded project: \(project.name)"
            validate()
        } catch {
            statusMessage = "Load failed: \(error.localizedDescription)"
        }
    }

    func saveProject(to url: URL) {
        do {
            try ProjectStore.saveProject(project, to: url)
            statusMessage = "Project saved."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func saveResultJSON(to url: URL) {
        guard let result else { return }
        do {
            try ProjectStore.saveResult(result, to: url)
            statusMessage = "Result JSON exported."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func saveCSV(to url: URL) {
        guard let result else { return }
        do {
            try CSVExporter.export(project: project, result: result).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "CSV exported."
        } catch {
            statusMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }

    func saveICS(for student: Student, to url: URL) {
        guard let result else { return }
        do {
            try ICSExporter.export(for: student, project: project, result: result).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "ICS exported for \(student.displayName)."
        } catch {
            statusMessage = "ICS export failed: \(error.localizedDescription)"
        }
    }
}
