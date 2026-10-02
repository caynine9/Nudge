import AppKit
import SwiftUI

struct PlaygroundMenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text(appState.isDemoMode ? "Nudge Playground" : "Nudge")
            .font(.headline)
        Text(appState.isDemoMode ? "Simulated session · Demo" : appState.socketStatus)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Toggle("Demo playground", isOn: Binding(
            get: { appState.isDemoMode },
            set: { appState.setDemoMode($0) }
        ))

        Button(appState.wantsPanelVisible ? "Expand Nudge" : "Show Nudge") {
            appState.showPanel()
        }
        .keyboardShortcut("o")

        if appState.isDemoMode {
            Button("Monitor preview") {
                appState.choose(.toolUse)
                appState.showPanel()
            }
            Button("Approval preview") { appState.choose(.waitingPermission) }
            Button("Question preview") { appState.choose(.waitingInput) }
            Button("Minimized preview") {
                appState.choose(.thinking)
                appState.dispatch(.collapse)
            }
            Menu("Preview host") {
                ForEach(CodexHost.allCases) { host in
                    Button(host.title) { appState.host = host }
                }
            }
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
        }

        Menu("Codex hooks") {
            Picker("Host configuration", selection: $appState.integrationHost) {
                ForEach(CodexHost.allCases) { host in Text(host.title).tag(host) }
            }
            let target = appState.configurationTarget(for: appState.integrationHost)
            Text("\(target.confidence): \(target.hooksFile.path)")
                .font(.caption)
            if let issue = target.resolutionIssue {
                Text(issue).font(.caption).foregroundStyle(.orange)
            }
            Text("Nudge manages hooks.json. Codex may also load hooks from config.toml and merge both sources.")
                .font(.caption)
            Text("Listener: \(appState.socketStatus)")
                .font(.caption)
            Text(appState.hookObservationStatus)
                .font(.caption)
            Text(appState.integrationStatus)
                .font(.caption)
            Button("Choose configuration folder…") { appState.chooseConfigurationFolder() }
            if target.confidence == "user-selected" {
                Button("Use default candidate") { appState.resetConfigurationFolder() }
            }
            Button("Install hooks for \(appState.integrationHost.title)") { appState.installCodexHooks() }
            Button("Remove Nudge hooks from selected config") { appState.removeCodexHooks() }
        }

        Button(appState.wantsPanelVisible ? "Hide overlay" : "Show overlay") {
            appState.togglePanel()
        }

        Divider()

        Button("Quit Nudge") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
