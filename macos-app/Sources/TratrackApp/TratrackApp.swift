import AppKit
import SwiftUI

@main
struct TratrackApp: App {
    @State private var model = AppModel()

    init() {
        // `swift run` launches a bare executable with no app bundle; make it
        // a regular app so it gets a Dock icon, menus and keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Tratrack") {
            ContentView(model: model)
                .onAppear { NSApplication.shared.activate() }
        }
        .commands {
            CommandMenu("Actions") {
                Button("Analyze…", action: model.openAnalysisDialog)
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Load JSON…", action: model.loadJSON)
                    .keyboardShortcut("o")
            }
        }
    }
}
