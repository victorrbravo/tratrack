import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var workflow: Workflow?
    var workflowFileName: String?
    var movieURL: URL?
    var query = ""
    var status: String?

    init() {
        // `swift run TratrackApp path/to/workflow.json` opens that file.
        if let path = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".json") }) {
            loadWorkflow(from: URL(fileURLWithPath: path))
        }
    }

    /// The workflow's name, or the file name when the workflow has none.
    var title: String {
        if let name = workflow?.name, !name.isEmpty {
            return name
        }
        return workflowFileName ?? "Untitled"
    }

    var canRun: Bool {
        movieURL != nil || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func loadJSON() {
        if let url = chooseFile(of: .json) {
            loadWorkflow(from: url)
        }
    }

    func loadVideo() {
        if let url = chooseFile(of: .mpeg4Movie) {
            movieURL = url
            status = nil
        }
    }

    func loadWorkflow(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            workflow = try Workflow.decode(from: data)
            workflowFileName = url.deletingPathExtension().lastPathComponent
            status = nil
        } catch {
            status = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Opens a dropped file: a .json workflow or an .mp4 movie.
    func open(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "json":
            loadWorkflow(from: url)
            return true
        case "mp4", "m4v":
            movieURL = url
            status = nil
            return true
        default:
            return false
        }
    }

    func run() {
        guard canRun else { return }
        // Not connected to the service yet; show what would be sent.
        var parts: [String] = []
        if let movieURL {
            parts.append("movie \(movieURL.lastPathComponent)")
        }
        let query = query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            parts.append("query “\(query)”")
        }
        status = "Run isn't connected to the service yet (\(parts.joined(separator: ", ")))."
    }

    private func chooseFile(of type: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
