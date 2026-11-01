import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let status = model.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
            for url in urls {
                opened = model.open(url) || opened
            }
            return opened
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: model.loadVideo) {
                Label(model.movieURL?.lastPathComponent ?? "Load MP4", systemImage: "film")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
            }
            .help(model.movieURL?.path ?? "Load an MP4 video")

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
