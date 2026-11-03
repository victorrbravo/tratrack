import AVKit
import SwiftUI

struct VideoSegmentPlayerView: View {
    let url: URL
    let start: Double
    let end: Double

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(player: player)
                .frame(minWidth: 640, minHeight: 360)
            HStack {
                Text(String(format: "%.0f s \u{2013} %.0f s", start, end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onAppear { setup() }
        .onDisappear { player.pause() }
    }

    private func setup() {
        print("[VideoPlayer] \(url.lastPathComponent) [\(start)s – \(end)s]")
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        player.replaceCurrentItem(with: item)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { [player] _ in
            player.play()
        }
    }
}

// NSViewRepresentable avoids the SwiftUI VideoPlayer demangle crash in SPM apps.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}
