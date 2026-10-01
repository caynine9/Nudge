import AppKit
import SwiftUI

struct PlaygroundMenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text("Nudge Playground")
            .font(.headline)
        Text("Simulated session · M0")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Button(appState.wantsPanelVisible ? "Expand Nudge" : "Show Nudge") {
            appState.showPanel()
        }
        .keyboardShortcut("o")

        Menu("Simulate phase") {
            ForEach(SessionPhase.allCases) { phase in
                Button {
                    appState.choose(phase)
                } label: {
                    if appState.presentation.snapshot.phase == phase {
                        Label(phase.title, systemImage: "checkmark")
                    } else {
                        Text(phase.title)
                    }
                }
            }
        }

        Button("New simulated turn", systemImage: "arrow.clockwise") {
            appState.beginNewTurn()
        }

        Button(appState.wantsPanelVisible ? "Hide overlay" : "Show overlay") {
            appState.togglePanel()
        }

        Divider()

        Button("Quit Nudge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
