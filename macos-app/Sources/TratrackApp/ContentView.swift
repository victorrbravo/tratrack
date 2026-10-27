import SwiftUI

struct ContentView: View {
    @State private var status = "Unknown"

    var body: some View {
        VStack(spacing: 16) {
            Text("Tratrack")
                .font(.largeTitle)
            Text("Service status: \(status)")
            Button("Check service") {
                Task { await checkHealth() }
            }
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
    }

    private func checkHealth() async {
        let url = URL(string: "http://localhost:8080/health")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let body = try JSONDecoder().decode([String: String].self, from: data)
            status = body["status"] ?? "Unknown"
        } catch {
            status = "Unreachable"
        }
    }
}
