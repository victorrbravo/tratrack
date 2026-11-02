import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Muse API Key")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("Enter API key…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                    .onSubmit { save() }
                Text("Used for video upload and analysis. Stored in app preferences.")
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
        .onAppear { draft = model.apiKey }
    }

    private func save() {
        model.apiKey = draft
        UserDefaults.standard.set(draft, forKey: "modelAPIKey")
        dismiss()
    }
}
