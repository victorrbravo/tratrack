import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Muse API Key")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("Enter API key…", text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                    .onSubmit { save() }
                Text("Used for video upload and analysis. Stored in app preferences.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("File ID")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !model.fileIDInput.isEmpty {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                TextField("File ID from uploaded video…", text: $model.fileIDInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                Text("Set automatically after uploading a video. You can also paste a file ID here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ticket")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !model.ticketString.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                TextField("Ticket number from analysis result…", text: $model.ticketString)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                    .onChange(of: model.ticketString) { _, new in
                        UserDefaults.standard.set(new, forKey: "analysisTicket")
                    }
                Text("Set automatically after analysis completes. Required for View Path.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .onAppear { draftKey = model.apiKey }
    }

    private func save() {
        model.apiKey = draftKey
        UserDefaults.standard.set(draftKey, forKey: "modelAPIKey")
        dismiss()
    }
}
