import SwiftUI

struct TipsDialogView: View {
    let stepName: String
    let tips: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stepName)
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 15))
                                .frame(width: 20)
                                .padding(.top, 1)
                            Text(tip)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
            }
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 420)
    }
}
