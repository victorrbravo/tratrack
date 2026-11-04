import AppKit
import Observation
import UniformTypeIdentifiers

struct VideoSegment: Identifiable {
    let id = UUID()
    let url: URL
    let start: Double
    let end: Double
}

struct TipsState: Identifiable {
    let id = UUID()
    let stepName: String
    let tips: [String]
}

struct PendingTag: Identifiable {
    let id = UUID()
    let stepDataId: Int
    let stepName: String
}

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
    var isLoadingWorkflow = false
    var isVideoLoaded = false
    var localVideoURL: URL?
    var activeVideoSegment: VideoSegment?
    var activeTips: TipsState?
    var pendingTag: PendingTag?
    var ticketString: String = UserDefaults.standard.string(forKey: "analysisTicket") ?? ""
    var apiKey: String = UserDefaults.standard.string(forKey: "modelAPIKey") ?? ""
    private var analysisTask: Task<Void, Never>?
    private var uploadTask: Task<Void, Never>?
    private var workflowTask: Task<Void, Never>?

    init() {
        // `swift run TratrackApp path/to/workflow.json` opens that file.
        if let path = CommandLine.arguments.dropFirst().first(where: { $0.hasSuffix(".json") }) {
            loadWorkflow(from: URL(fileURLWithPath: path))
        }
    }

    /// The workflow's name, or the file name when the workflow has none or uses the generic "Stories" default.
    var title: String {
        if let name = workflow?.name, !name.isEmpty, name != "Stories" { return name }
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
        !isUploading && !fileIDInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func openAnalysisDialog() { showAnalysisDialog = true }
    func openSettings() { showSettings = true }

    func openTips(for step: Step) {
        guard let tipsId = step.tipsIdField else {
            status = "Step \"\(step.name)\" has no tips."
            return
        }
        let order = "action: show_step_tips\ntips_id: \(tipsId)\n"
        status = "Loading tips for \(step.name)…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let json = try await AnalysisServiceClient().callStories(order: order)
                let tips = try Self.parseTips(from: json)
                self.activeTips = TipsState(stepName: step.name, tips: tips)
                self.status = nil
            } catch {
                self.status = "Failed to load tips: \(error.localizedDescription)"
            }
        }
    }

    func openAddTag(for step: Step) {
        guard let dataId = step.taskDataId else {
            status = "Step \"\(step.name)\" has no ID."
            return
        }
        pendingTag = PendingTag(stepDataId: dataId, stepName: step.name)
    }

    func addTag(stepDataId: Int, tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let order = "action: add_tag_by_pk_tracking\npk_tracking: \(stepDataId)\ntag: \(trimmed)\n"
        status = "Adding tag…"
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await AnalysisServiceClient().callStories(order: order)
                self.status = nil
                self.loadWorkflowFromStories()
            } catch {
                self.status = "Failed to add tag: \(error.localizedDescription)"
            }
        }
    }

    private static func parseTips(from json: String) throws -> [String] {
        struct TipItem: Decodable { let tip: String }
        struct TipsWrapper: Decodable { let tips: [TipItem]? }

        guard var data = json.data(using: .utf8) else { throw CocoaError(.fileReadUnknown) }
        if let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }),
           start > data.startIndex { data = Data(data[start...]) }

        let decoder = JSONDecoder()
        func unescape(_ s: String) -> String { s.replacingOccurrences(of: "#comma#", with: ",") }
        if let wrapper = try? decoder.decode(TipsWrapper.self, from: data), let items = wrapper.tips {
            return items.map { unescape($0.tip) }
        }
        if let items = try? decoder.decode([TipItem].self, from: data) {
            return items.map { unescape($0.tip) }
        }
        throw CocoaError(.fileReadUnknown)
    }

    func openLocation(for step: Step, inGoogle: Bool = false) {
        guard let coord = step.coordinate else {
            status = "Step \"\(step.name)\" has no location data."
            return
        }
        let name = step.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? step.name
        let url: URL?
        if inGoogle {
            url = URL(string: "https://maps.google.com/maps?q=\(coord.lat),\(coord.lon)(\(name))")
        } else {
            url = URL(string: "maps://?ll=\(coord.lat),\(coord.lon)&q=\(name)")
        }
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    func openVideoSegment(for step: Step) {
        guard let url = localVideoURL else {
            status = "No local video — click Upload Video and choose Local Only first."
            return
        }
        guard let seg = step.videoSegment else {
            status = "Step \"\(step.name)\" has no video segment data."
            return
        }
        print("[AppModel] openVideoSegment \(step.name) [\(seg.start)s – \(seg.end)s] url=\(url.lastPathComponent)")
        activeVideoSegment = VideoSegment(url: url, start: seg.start, end: seg.end)
    }

    func loadJSON() {
        let examples = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("examples")
        if let url = chooseFile(of: .json, in: examples) {
            loadWorkflow(from: url)
        }
    }

    /// Picks an mp4, then asks whether to upload to AI or use locally only.
    /// "Local only" stores the path for video-segment playback without uploading.
    /// "Upload to AI" sends it to the Muse Files API and stores the returned file_id.
    func uploadVideo() {
        guard let url = chooseFile(of: .mpeg4Movie) else { return }
        guard url.pathExtension.lowercased() == "mp4" else {
            status = "Only .mp4 files are accepted (got .\(url.pathExtension))."
            return
        }
        let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let limitBytes = 50 * 1024 * 1024
        guard fileSizeBytes <= limitBytes else {
            let mb = Double(fileSizeBytes) / (1024 * 1024)
            status = String(format: "File too large (%.1f MB). Maximum is 50 MB.", mb)
            return
        }

        localVideoURL = url
        isVideoLoaded = false

        let alert = NSAlert()
        alert.messageText = "Upload \(url.lastPathComponent) to AI?"
        alert.informativeText = "Upload it for AI analysis, or save the path locally to view video segments without uploading."
        alert.addButton(withTitle: "Upload to AI")
        alert.addButton(withTitle: "Local Only")
        alert.alertStyle = .informational

        if alert.runModal() == .alertSecondButtonReturn {
            fileIDInput = url.path
            isVideoLoaded = true
            status = "Video saved locally — ready to search."
            return
        }

        guard !apiKey.isEmpty else {
            status = "Set your Muse API key in Settings first."
            showSettings = true
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
            localVideoURL = url
            status = nil
            return true
        default:
            return false
        }
    }

    /// Starts the analysis using `fileIDInput`.
    func run() {
        let idFile = fileIDInput.trimmingCharacters(in: .whitespaces)
        guard !idFile.isEmpty else {
            print("[AppModel] run() called but fileIDInput is empty — doing nothing")
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
            if let t = parseTicket(from: update.resultJSON) {
                ticketString = "\(t)"
                UserDefaults.standard.set(ticketString, forKey: "analysisTicket")
                print("[AppModel] → ticket=\(t) saved to settings")
            }
            status = "Analysis finished (job \(update.jobID))."
            analysisProgress = nil
            isVideoLoaded = true
            AnalysisNotifier.notifyFinished(jobID: update.jobID, failed: false)
        } else {
            print("[AppModel] → in progress")
            status = "Analysis \(update.status.lowercased())… \(update.progress)%"
        }
    }

    /// Calls the CallStories gRPC method with a show_flow_data order using the
    /// ticket stored in settings, then loads the returned JSON into the canvas.
    func loadWorkflowFromStories() {
        let ticket = ticketString.trimmingCharacters(in: .whitespaces)
        guard !ticket.isEmpty else { return }

        let filter = query.trimmingCharacters(in: .whitespaces)
        let order = """
        action: show_flow_data
        ticket: \(ticket)
        filter: \(filter)
        by_day: false
        page_number: 1
        page_size: 70
        """

        workflowTask?.cancel()
        isLoadingWorkflow = true
        status = "Loading workflow for ticket \(ticket)…"

        workflowTask = Task { [weak self] in
            guard let self else { return }
            print("[AppModel] loadWorkflowFromStories ticket=\(ticket)")
            do {
                let json = try await AnalysisServiceClient().callStories(order: order)
                print("[AppModel] loadWorkflowFromStories: received \(json.count) chars")
                guard var data = json.data(using: .utf8) else {
                    throw CocoaError(.fileReadUnknown)
                }
                if let start = data.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "[") }),
                   start > data.startIndex {
                    data = Data(data[start...])
                }
                var loaded = try Workflow.decode(from: data)
                loaded.tasks = loaded.tasks.filter { $0.name != "Start" }
                self.workflow = loaded
                self.workflowFileName = "ticket-\(ticket)"
                self.isLoadingWorkflow = false
                self.status = "Workflow loaded for ticket \(ticket)."
            } catch {
                print("[AppModel] loadWorkflowFromStories error: \(error)")
                self.isLoadingWorkflow = false
                self.status = "Failed to load workflow: \(error.localizedDescription)"
            }
        }
    }

    private func parseTicket(from json: String) -> Int? {
        struct Result: Decodable { var ticket: Int? }
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(Result.self, from: data)
        else { return nil }
        return result.ticket
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
