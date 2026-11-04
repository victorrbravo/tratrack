import SwiftUI

struct AddTagDialogView: View {
    let pending: PendingTag
    let onAdd: (Int, String) -> Void

    @State private var tagText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Tag")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text(pending.stepName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Enter tag…", text: $tagText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 300)
                    .onSubmit { submit() }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Tag") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(tagText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func submit() {
        let trimmed = tagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()
        onAdd(pending.stepDataId, trimmed)
    }
}
