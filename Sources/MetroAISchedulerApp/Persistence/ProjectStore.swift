import Foundation

enum ProjectStore {
    static func saveProject(_ project: ScheduleTemplateProject, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project).write(to: url)
    }

    static func loadProject(from url: URL) throws -> ScheduleTemplateProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScheduleTemplateProject.self, from: Data(contentsOf: url))
    }

    static func saveResult(_ result: ScheduleResult, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: url)
    }
}
