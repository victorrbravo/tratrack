import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    var workflow: Workflow?
    var workflowFileName: String?
    var fileIDInput = ""
    var showAnalysisDialog = false
    var showSettings = false
    var query = ""
    var status: String?
    var currentJobID: String?
    var analysisProgress: Int?
    var lastResultJSON: String?
    var isUploading = false
    var apiKey: String = UserDefaults.standard.string(forKey: "modelAPIKey") ?? ""
    private var analysisTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?

    init() {
        // `swift run TratrackApp path/to/workflow.json` opens that file.
        if let path = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".json") }) {
            loadWorkflow(from: URL(fileURLWithPath: path))
        }
    }

    /// The workflow's name, or the file name when the workflow has none.
    var title: String {
        if let name = workflow?.name, !name.isEmpty { return name }
        return workflowFileName ?? "Untitled"
    }

    /// Label shown on the Analyze button — last path component when the
    /// input looks like a file path, otherwise the raw ID (truncated).
    var fileIDLabel: String {
        let id = fileIDInput.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return "Analyze…" }
        let last = URL(fileURLWithPath: id).lastPathComponent
        return last.isEmpty ? id : last
    }

    var canRun: Bool {
        !isUploading &&
        (!fileIDInput.trimmingCharacters(in: .whitespaces).isEmpty ||
         !query.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func openAnalysisDialog() { showAnalysisDialog = true }
    func openSettings() { showSettings = true }

    func loadJSON() {
        let examples = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("examples")
        if let url = chooseFile(of: .json, in: examples) {
            loadWorkflow(from: url)
        }
    }

    /// Picks an mp4, uploads it to the Muse Files API, and stores the returned file_id
    /// in fileIDInput so the Analyze/Run button becomes enabled.
    func uploadVideo() {
        guard !apiKey.isEmpty else {
            status = "Set your Muse API key in Settings first."
            showSettings = true
            return
        }
        guard let url = chooseFile(of: .mpeg4Movie) else { return }
        guard url.pathExtension.lowercased() == "mp4" else {
            status = "Only .mp4 files are accepted (got .\(url.pathExtension))."
            return
        }

        uploadTask?.cancel()
        isUploading = true
        fileIDInput = ""
        status = "Uploading \(url.lastPathComponent)…"

        let apiKeyCopy = apiKey
        uploadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fileID = try await UploadClient(apiKey: apiKeyCopy).upload(videoURL: url)
                self.fileIDInput = fileID
                self.isUploading = false
                self.status = "Upload complete — ready to analyze."
            } catch {
                print("[AppModel] uploadVideo error: \(error)")
                self.isUploading = false
                self.status = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    func loadWorkflow(from url: URL) {
        do {
            var data = try Data(contentsOf: url)
            // Strip leading garbage bytes before the first JSON delimiter.
            // Some outputs from the stories-service prepend a stray byte (e.g. 'i')
            // before the opening '{'.
            if let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }),
               start > data.startIndex {
                data = Data(data[start...])
            }
            workflow = try Workflow.decode(from: data)
            workflowFileName = url.deletingPathExtension().lastPathComponent
            status = nil
        } catch {
            status = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Opens a dropped file: a .json workflow or an .mp4 whose path becomes the file ID.
    func open(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "json":
            loadWorkflow(from: url)
            return true
        case "mp4", "m4v":
            fileIDInput = url.path
            status = nil
            return true
        default:
            return false
        }
    }

    /// Starts the analysis using `fileIDInput` if set, otherwise `query`.
    func run() {
        let fileID = fileIDInput.trimmingCharacters(in: .whitespaces)
        let idFile = !fileID.isEmpty ? fileID : query.trimmingCharacters(in: .whitespaces)
        guard !idFile.isEmpty else {
            print("[AppModel] run() called but idFile is empty — doing nothing")
            return
        }

        print("[AppModel] run() starting analysis for idFile=\(idFile)")
        analysisTask?.cancel()
        currentJobID = nil
        analysisProgress = 0
        status = "Starting analysis…"

        // StartAnalysis returns a job id immediately; SubscribeAnalysis then
        // pushes updates, so this task waits to be notified when the job finishes.
        analysisTask = Task { [weak self] in
            guard let self else { return }
            print("[AppModel] Task started for idFile=\(idFile)")
            do {
                try await AnalysisServiceClient().startAndWatch(idFile: idFile) { [self] update in
                    await self.handle(update)
                }
                print("[AppModel] startAndWatch returned normally")
            } catch {
                print("[AppModel] startAndWatch threw: \(error)")
                self.status = "Analysis service unreachable: \(error.localizedDescription)"
                self.analysisProgress = nil
            }
            print("[AppModel] Task finished for idFile=\(idFile)")
        }
    }

    private func handle(_ update: AnalysisUpdate) {
        print("[AppModel] handle: jobID=\(update.jobID) status=\(update.status) progress=\(update.progress)% error=\(update.error.isEmpty ? "none" : update.error)")
        currentJobID = update.jobID
        analysisProgress = update.progress
        if update.isFailed {
            print("[AppModel] → FAILED")
            status = "Analysis failed: \(update.error)"
            analysisProgress = nil
            AnalysisNotifier.notifyFinished(jobID: update.jobID, failed: true)
        } else if update.isFinished {
            print("[AppModel] → COMPLETED, resultJSON length=\(update.resultJSON.count)")
            lastResultJSON = update.resultJSON
            status = "Analysis finished (job \(update.jobID))."
            analysisProgress = nil
            AnalysisNotifier.notifyFinished(jobID: update.jobID, failed: false)
        } else {
            print("[AppModel] → in progress")
            status = "Analysis \(update.status.lowercased())… \(update.progress)%"
        }
    }

    private func chooseFile(of type: UTType, in directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [type]
        panel.allowsMultipleSelection = false
        if let directory {
            panel.directoryURL = directory
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
