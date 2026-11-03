import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let status = model.status {
                HStack(spacing: 8) {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if model.isUploading {
                        ProgressView()
                            .controlSize(.small)
                    } else if let progress = model.analysisProgress {
                        ProgressView(value: Double(progress), total: 100)
                            .frame(width: 120)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()

            if let workflow = model.workflow {
                WorkflowCanvas(
                    kicker: [model.workflowFileName, workflow.data?.amountField]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    title: model.title,
                    steps: workflow.steps,
                    onStepDoubleClick: { step in model.openVideoSegment(for: step) },
                    onStepTips: { step in model.openTips(for: step) }
                )
            } else {
                emptyState
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .dropDestination(for: URL.self) { urls, _ in
            var opened = false
            for url in urls { opened = model.open(url) || opened }
            return opened
        }
        .sheet(isPresented: $model.showAnalysisDialog) {
            AnalysisDialogView(model: model)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView(model: model)
        }
        .sheet(item: $model.activeVideoSegment) { seg in
            VideoSegmentPlayerView(url: seg.url, start: seg.start, end: seg.end)
        }
        .sheet(item: $model.activeTips) { state in
            TipsDialogView(stepName: state.stepName, tips: state.tips)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            // Upload button — icon and label reflect current state
            Button(action: model.uploadVideo) {
                if model.isUploading {
                    Label("Uploading…", systemImage: "arrow.up.circle")
                } else if !model.fileIDInput.isEmpty {
                    Label("Replace Video", systemImage: "video.fill")
                } else {
                    Label("Upload Video", systemImage: "arrow.up.circle")
                }
            }
            .disabled(model.isUploading)
            .help(
                model.isUploading ? "Upload in progress…" :
                model.fileIDInput.isEmpty ? "Pick an .mp4 and upload it to Muse" :
                "Upload a different video (current: \(model.fileIDInput))"
            )

            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)

            // Analyze — disabled until a file ID is obtained from upload
            Button(action: model.run) {
                Label("Analyze", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)
            .help(model.fileIDInput.isEmpty ? "Upload a video first" : "Run analysis for \(model.fileIDInput)")

            // View Path — enabled once analysis returns a ticket
            Button(action: model.loadWorkflowFromStories) {
                if model.isLoadingWorkflow {
                    Label("Loading…", systemImage: "arrow.down.circle")
                } else {
                    Label("View Path", systemImage: "arrow.down.circle")
                }
            }
            .disabled(model.ticketString.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoadingWorkflow)
            .help(model.ticketString.isEmpty ? "Run analysis first, or set a ticket in Settings" : "View workflow path for ticket \(model.ticketString)")

            Button(action: model.openSettings) {
                Image(systemName: "gear")
            }
            .help("Settings")
        }
        .controlSize(.large)
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Paper.muted)
            Text("No workflow loaded")
                .font(.title2.bold())
                .foregroundStyle(Paper.ink)
            Text("Drop a .json file here, or use Actions ▸ Load JSON.")
                .foregroundStyle(Paper.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Paper.background)
    }
}

private struct AnalysisDialogView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start Analysis")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("File ID")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Enter Muse file ID…", text: $model.fileIDInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                    .onSubmit { startIfReady() }
                Text("Upload a video first to obtain a file ID automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let status = model.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.showAnalysisDialog = false }
                    .keyboardShortcut(.cancelAction)
                Button("Run Analysis") { startIfReady() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.fileIDInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func startIfReady() {
        guard !model.fileIDInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.showAnalysisDialog = false
        model.run()
    }
}
