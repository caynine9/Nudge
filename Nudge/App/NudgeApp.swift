import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(NudgeAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            PlaygroundMenuView()
                .environmentObject(appState)
        } label: {
            Label("Nudge", systemImage: "sparkles")
        }
        .menuBarExtraStyle(.menu)
    }
}
