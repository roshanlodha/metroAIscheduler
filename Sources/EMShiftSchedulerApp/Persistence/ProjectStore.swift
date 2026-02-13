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

    static func saveShiftBundle(_ bundle: ShiftBundleTemplate, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(to: url)
    }

    static func loadShiftBundle(from url: URL) throws -> ShiftBundleTemplate {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url)
        if let bundle = try? decoder.decode(ShiftBundleTemplate.self, from: data) {
            return bundle
        }
        let shifts = try decoder.decode([ShiftTemplate].self, from: data)
        return ShiftBundleTemplate(name: "Imported Schedule", shifts: shifts)
    }
}
