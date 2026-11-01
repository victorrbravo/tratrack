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
    var currentJobID: String?
    var analysisProgress: Int?
    var lastResultJSON: String?
    private var analysisTask: Task<Void, Never>?

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
        let idFile = movieURL?.path ?? query.trimmingCharacters(in: .whitespaces)
        guard !idFile.isEmpty else { return }
        analysisTask?.cancel()
        currentJobID = nil
        analysisProgress = 0
        status = "Starting analysis…"
        // StartAnalysis returns a job id immediately; SubscribeAnalysis then
        // pushes updates, so this task just waits to be notified that the
        // long (5-8 min) job finished — no polling.
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await AnalysisServiceClient().startAndWatch(idFile: idFile) { [self] update in
                    await self.handle(update)
                }
            } catch {
                self.status = "Analysis service unreachable: \(error.localizedDescription)"
                self.analysisProgress = nil
            }
        }
    }

    private func handle(_ update: AnalysisUpdate) {
        currentJobID = update.jobID
        analysisProgress = update.progress
        if update.isFailed {
            status = "Analysis failed: \(update.error)"
            analysisProgress = nil
            AnalysisNotifier.notifyFinished(jobID: update.jobID, failed: true)
        } else if update.isFinished {
            lastResultJSON = update.resultJSON
            status = "Analysis finished (job \(update.jobID))."
            analysisProgress = nil
            AnalysisNotifier.notifyFinished(jobID: update.jobID, failed: false)
        } else {
            status = "Analysis \(update.status.lowercased())… \(update.progress)%"
        }
    }

    private func chooseFile(of type: UTType) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
