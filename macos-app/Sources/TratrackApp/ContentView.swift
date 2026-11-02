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
                    steps: workflow.steps
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
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            // Upload video → Muse Files API → populates fileIDInput
            Button(action: model.uploadVideo) {
                if model.isUploading {
                    Label("Uploading…", systemImage: "arrow.up.circle")
                } else {
                    Label("Upload Video", systemImage: "arrow.up.circle")
                }
            }
            .disabled(model.isUploading)
            .help(model.isUploading ? "Upload in progress…" : "Pick an .mp4 and upload it to Muse")

            // Shows the current file ID; tap to change it manually
            Button(action: model.openAnalysisDialog) {
                Label(model.fileIDLabel, systemImage: "film")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
            }
            .help(
                model.fileIDInput.isEmpty
                    ? "Enter a Muse file ID to start analysis"
                    : model.fileIDInput
            )

            Button(action: model.loadJSON) {
                Label(model.workflowFileName.map { "\($0).json" } ?? "Load JSON", systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
            }
            .help("Load a workflow JSON and draw its tasks")

            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(model.run)

            Button(action: model.run) {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRun)

            Button(action: model.openSettings) {
                Image(systemName: "gear")
            }
            .help("Settings — Muse API key and preferences")
        }
        .controlSize(.large)
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Paper.muted)
            Text("No workflow loaded")
                .font(.title2.bold())
                .foregroundStyle(Paper.ink)
            Text("Choose Actions ▸ Load JSON, or drop a .json file here.")
                .foregroundStyle(Paper.muted)
            Button("Load JSON…", action: model.loadJSON)
                .padding(.top, 4)
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
                Button("Cancel") {
                    model.showAnalysisDialog = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Run Analysis") {
                    startIfReady()
                }
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
