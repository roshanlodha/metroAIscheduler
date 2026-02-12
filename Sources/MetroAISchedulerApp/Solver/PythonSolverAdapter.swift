import Foundation

final class PythonSolverAdapter: SolverAdapter {
    private let fileManager = FileManager.default

    func solve(project: ScheduleTemplateProject, shiftInstances: [GeneratedShiftInstance]) throws -> ScheduleResult {
        guard !project.students.isEmpty else {
            throw SolverError.invalidInput("Add at least one student before generating a schedule.")
        }
        guard !shiftInstances.isEmpty else {
            throw SolverError.invalidInput("No shift instances were generated for the selected block/rules.")
        }

        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("metro-ai-scheduler", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let inputURL = tempRoot.appendingPathComponent("solver-input-\(UUID().uuidString).json")
        let outputURL = tempRoot.appendingPathComponent("solver-output-\(UUID().uuidString).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(PythonSolverInput(project: project, shiftInstances: shiftInstances)).write(to: inputURL)

        guard let scriptURL = solverScriptURL() else {
            throw SolverError.executionFailed("Solver script resource not found.")
        }

        let process = Process()
        let pythonPath = resolvePythonExecutablePath()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptURL.path, inputURL.path, outputURL.path]

        var env = ProcessInfo.processInfo.environment
        if let pythonHome = resolveBundledPythonHome() {
            env["PYTHONHOME"] = pythonHome.path
            let bundledSitePackages = pythonHome
                .appendingPathComponent("lib", isDirectory: true)
                .appendingPathComponent("python3.12", isDirectory: true)
                .appendingPathComponent("site-packages", isDirectory: true)
                .path
            let existing = env["PYTHONPATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            env["PYTHONPATH"] = existing.map { $0.isEmpty ? bundledSitePackages : "\(bundledSitePackages):\($0)" } ?? bundledSitePackages
        }
        process.environment = env

        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SolverError.executionFailed("Failed to start python3 process: \(error.localizedDescription)")
        }

        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let errMessage = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw SolverError.executionFailed("Solver process failed. \(errMessage)")
        }

        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw SolverError.executionFailed("Solver did not produce output. \(errMessage)")
        }

        let data = try Data(contentsOf: outputURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let output = try decoder.decode(PythonSolverOutput.self, from: data)

        if output.status.uppercased() != "FEASIBLE" && output.status.uppercased() != "OPTIMAL" {
            let diagnostic = output.diagnostic ?? SolverDiagnostic(message: "No feasible solution found.", details: [])
            throw SolverError.infeasible(diagnostic)
        }

        return ScheduleResult(generatedAt: Date(), shiftInstances: shiftInstances, assignments: output.assignments)
    }

    private func solverScriptURL() -> URL? {
#if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "ortools_solver", withExtension: "py")
#else
        return Bundle.main.url(forResource: "ortools_solver", withExtension: "py")
#endif
    }

    private func resolvePythonExecutablePath() -> String {
        if let override = ProcessInfo.processInfo.environment["METRO_AI_PYTHON"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }
        if let bundledPython = resolveBundledPythonHome()?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3", isDirectory: false)
            .path,
           fileManager.isExecutableFile(atPath: bundledPython) {
            return bundledPython
        }
        return "/usr/bin/python3"
    }

    private func resolveBundledPythonHome() -> URL? {
        let candidates = [Bundle.main.resourceURL].compactMap { $0 }
        for resourceURL in candidates {
            let home = resourceURL.appendingPathComponent("python", isDirectory: true)
            if fileManager.fileExists(atPath: home.path) {
                return home
            }
        }
        return nil
    }
}
