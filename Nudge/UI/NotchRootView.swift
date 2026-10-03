import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let displayKind: DisplayKind
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let compactWidth: CGFloat
    var availableWidth: CGFloat = .infinity
    var availableHeight: CGFloat = .infinity
    var visibleSizeChanged: ((CGSize) -> Void)? = nil
    @State private var lastOpenSize: CGSize?
    @State private var lastOpenMode: NotchPresentation = .peek
    @State private var lastFeedback: InteractionFeedback?
    @State private var scrollAnchorSessionID: String?
    var hoverChanged: ((Bool) -> Void)? = nil

    private var mode: NotchPresentation { appState.presentation.mode }
    private var phase: SessionPhase { appState.presentation.snapshot.phase }
    private var displayedPhaseTitle: String {
        guard !isDemo else { return phase.title }
        if phase == .toolUse { return "Working" }
        if phase == .completed { return "Turn finished" }
        return phase.title
    }
    private var isDemo: Bool { appState.isDemoMode }
    private var focusedTitle: String {
        isDemo ? PlaygroundScenario.taskTitle : appState.presentation.snapshot.projectLabel
    }
    private var isNotched: Bool { displayKind == .notch }
    private var targetSize: CGSize {
        let preferred = NotchGeometry.preferredSize(kind: displayKind, compactWidth: compactWidth,
                                                   notchHeight: notchHeight, mode: mode, phase: phase,
                                                   activeSessionCount: appState.activeSessions.count)
        return CGSize(width: min(preferred.width, availableWidth), height: min(preferred.height, availableHeight))
    }
    private var reduceMotion: Bool { appState.reduceMotion || accessibilityReduceMotion }

    private var contentMode: NotchPresentation { mode == .collapsed ? lastOpenMode : mode }
    private var displaysUsageLimits: Bool {
        (mode == .peek || mode == .expanded) && !phase.isAttention
    }

    private var openSize: CGSize {
        if mode != .collapsed { return targetSize }
        if let lastOpenSize { return lastOpenSize }
        let preferred = NotchGeometry.preferredSize(kind: displayKind, compactWidth: compactWidth,
                                                   notchHeight: notchHeight, mode: .peek, phase: phase,
                                                   activeSessionCount: appState.activeSessions.count)
        return CGSize(width: min(preferred.width, availableWidth),
                      height: min(preferred.height, availableHeight))
    }

    // A semantic page change dissolves its content while the shell keeps moving.
    // Use the retained content mode so collapsing does not replace a receipt with
    // the monitor underneath it halfway through the exit animation.
    private var contentIdentity: String {
        if contentMode == .confirmation {
            return "confirmation-\((appState.presentation.feedback ?? lastFeedback)?.label ?? "")"
        }
        switch phase {
        case .waitingPermission: return "permission"
        case .waitingInput: return "question"
        default: return "monitor"
        }
    }

    private var expandedPage: some View {
        VStack(spacing: 0) {
            if isNotched { Color.clear.frame(height: notchHeight).accessibilityHidden(true) }
            if contentMode == .confirmation, let feedback = appState.presentation.feedback ?? lastFeedback {
                confirmation(feedback)
                    .frame(maxWidth: .infinity).frame(height: 46)
            } else {
                content
                    .padding(.horizontal, isNotched ? 28 : 16)
                    .padding(.top, 16).padding(.bottom, 14)
            }
            Spacer(minLength: 0)
        }
        // This frame belongs INSIDE each page identity. The outgoing page keeps
        // its own width while the new page and shell move to a different size.
        .frame(width: openSize.width, height: openSize.height, alignment: .top)
        .animation(nil, value: openSize)
    }

    private var contentLayers: some View {
        ZStack(alignment: .top) {
            Group {
                if isNotched { compactHeader }
                else { minimizedRow.padding(.horizontal, 12) }
            }
            .frame(width: min(compactWidth, availableWidth), height: isNotched ? notchHeight + 2 : 38)
            .blur(radius: mode != .collapsed && !reduceMotion ? 3 : 0)
            .opacity(mode == .collapsed ? 1 : 0)
            .allowsHitTesting(mode == .collapsed)
            .accessibilityHidden(mode != .collapsed)
            .disabled(mode != .collapsed)

            ZStack(alignment: .top) {
                expandedPage
                    .id(contentIdentity)
                    .transition(NotchMotion.pageTransition(reduceMotion: reduceMotion))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: contentIdentity)
            // One opacity curve in both directions; multiplying two fades made
            // the expanded content disappear too quickly during contraction.
            .modifier(NotchPageDissolve(amount: mode == .collapsed ? 1 : 0, reduceMotion: reduceMotion))
            .allowsHitTesting(mode != .collapsed)
            .accessibilityHidden(mode == .collapsed)
            .disabled(mode == .collapsed)
        }
    }

    var body: some View {
        // The shell owns layout. Retained open content is an overlay, so its ideal
        // size cannot inflate the collapsed shell or any other smaller state.
        Color.clear
        .overlay(alignment: .top) { contentLayers }
        .background { shell.fill(Color.black) }
        .clipShape(shell)
        .shadow(color: .black.opacity(mode == .collapsed ? 0 : 0.24), radius: 12, y: 5)
        .contentShape(shell)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            visibleSizeChanged?(size)
        }
        // Resolve animated geometry once before passing it to the shell, content and
        // pointer observer. Otherwise leaf views can each inherit different geometry.
        .geometryGroup()
        .frame(width: targetSize.width, height: targetSize.height, alignment: .top)
        .animation(reduceMotion ? nil : NotchMotion.shell(collapsing: mode == .collapsed), value: mode)
        .animation(reduceMotion ? nil : NotchMotion.shell(collapsing: false), value: phase)
        .animation(reduceMotion ? nil : NotchMotion.shell(collapsing: false),
                   value: mode == .expanded && appState.activeSessions.count > 1)
        // Rebuild at the current target when motion is disabled or the machine sleeps;
        // an in-flight animation must not carry across either boundary.
        .id(reduceMotion || appState.presentation.isSleeping)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onHover { inside in
            if let hoverChanged { hoverChanged(inside) }
            else { appState.dispatch(.pointerChanged(inside)) }
        }
        .onChange(of: mode, initial: true) { _, mode in
            if mode != .collapsed { lastOpenMode = mode }
            if let feedback = appState.presentation.feedback { lastFeedback = feedback }
        }
        .onChange(of: targetSize, initial: true) { _, size in
            if mode != .collapsed { lastOpenSize = size }
        }
        .onChange(of: accessibilityReduceMotion) { _, value in appState.setReduceMotion(value) }
        .onAppear { appState.setReduceMotion(accessibilityReduceMotion) }
        .task(id: "\(mode)-\(isDemo)-\(phase.isAttention)") {
            guard displaysUsageLimits, !isDemo else { return }
            while !Task.isCancelled {
                appState.refreshCodexUsageIfNeeded()
                do { try await Task.sleep(for: .seconds(300)) }
                catch { return }
            }
        }
        .accessibilityIdentifier("nudge.notch")
    }

    private var shell: NotchShell {
        NotchShell(attachedToScreenEdge: isNotched, compactWidth: compactWidth,
                   neckHeight: notchHeight + 2, fullWidth: mode != .collapsed)
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            mascot.scaleEffect(0.68).frame(width: 30, height: 24)
            Color.clear.frame(width: notchWidth).accessibilityHidden(true)
            Image(systemName: phase.symbol)
                .font(NotchType.readable(12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 30)
        }
        .frame(width: compactWidth, height: notchHeight + 2)
        .contentShape(Rectangle())
        .onTapGesture { appState.dispatch(.togglePinned) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(focusedTitle), \(displayedPhaseTitle)\(isDemo ? ", demo" : "")")
        .accessibilityHint("Expand or collapse the focused session")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { appState.dispatch(.togglePinned) }
    }

    private var minimizedRow: some View {
        Button { appState.dispatch(.togglePinned) } label: {
            HStack(spacing: 10) {
                mascot.scaleEffect(0.68).frame(width: 23, height: 24)
                Text(focusedTitle).font(NotchType.readable(12)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: phase.symbol).foregroundStyle(accent).font(NotchType.readable(10))
            }
            .frame(height: 38)
        }
        .buttonStyle(NotchButtonStyle(tone: .row))
        .accessibilityLabel("\(focusedTitle), \(displayedPhaseTitle)\(isDemo ? ", demo" : "")")
    }

    private var mascot: some View {
        Nudgie(pose: MascotPose(phase: phase), celebrationPulse: appState.celebrationPulse,
               attentionPulse: appState.attentionPulse,
               reduceMotion: reduceMotion, isSleeping: appState.presentation.isSleeping)
    }

    @ViewBuilder
    private var content: some View {
        if isDemo {
            switch phase {
            case .waitingPermission: permission
            case .waitingInput: question
            default: demoMonitor
            }
        } else {
            if phase.isAttention && contentMode != .expanded {
                liveAttention
            } else {
                liveMonitor
            }
        }
    }

    private var liveAttention: some View {
        let interaction = appState.presentation.snapshot.pendingInteraction
        let isPermission = phase == .waitingPermission
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: isPermission ? "hand.raised.fill" : "questionmark.bubble.fill")
                    .foregroundStyle(isPermission ? NotchPalette.orange : NotchPalette.cyan)
                Text(isPermission ? "Permission needed" : "Codex has a question")
                    .font(NotchType.readable(13, weight: .medium))
                    .foregroundStyle(isPermission ? NotchPalette.orange : NotchPalette.cyan)
                    .lineLimit(1)
                Spacer(minLength: 0)
                NotchBadge(title: appState.presentation.snapshot.projectLabel)
            }
            if let issue = appState.navigationIssue {
                Text(issue).font(NotchType.readable(11)).foregroundStyle(NotchPalette.orange).lineLimit(2)
            } else if let preview = interaction?.preview {
                Text(preview)
                    .font(NotchType.readable(12))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .truncationMode(.tail)
            } else if appState.presentation.snapshot.pendingInteractionOverflowed {
                Text("More requests need attention. Open Codex to review them.")
                    .font(NotchType.readable(11)).foregroundStyle(NotchPalette.secondary).lineLimit(2)
            } else if isPermission {
                Text("Codex is waiting for approval in its native prompt.")
                    .font(NotchType.readable(11)).foregroundStyle(NotchPalette.secondary).lineLimit(2)
            } else {
                Text("Open Codex to read and answer this question.")
                    .font(NotchType.readable(11)).foregroundStyle(NotchPalette.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Button {
                    appState.openAttentionInCodex()
                } label: {
                    HStack(spacing: 6) {
                        Text(appState.isOpeningHost ? "Opening…" : (isPermission ? "Open Codex Desktop" : "Answer in Codex Desktop"))
                            .lineLimit(1)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(NotchType.readable(11, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                }
                .buttonStyle(NotchButtonStyle(tone: .primary))
                .disabled(appState.isOpeningHost)
                .accessibilityHint("Activate Codex Desktop. This does not resolve the request.")
                Button { appState.toggleAttentionSessionList() } label: {
                    Image(systemName: "list.bullet")
                        .font(NotchType.readable(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(NotchButtonStyle(tone: .neutral))
                .accessibilityLabel("Show all active Codex sessions")
            }
            Text("For terminal work, return to its Codex CLI window.")
                .font(NotchType.readable(10))
                .foregroundStyle(NotchPalette.secondary)
                .lineLimit(1)
                .accessibilityHidden(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(isPermission ? "Permission needed" : "Question for you"), \(appState.presentation.snapshot.projectLabel)")
    }

    private var liveMonitor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displaysUsageLimits {
                HStack {
                    usageLimits
                    Spacer(minLength: 0)
                }
            }
            HStack {
                if appState.presentation.showsSessionList && phase.isAttention {
                    Button("Back to request") { appState.toggleAttentionSessionList() }
                        .font(NotchType.readable(11, weight: .medium))
                        .foregroundStyle(NotchPalette.cyan)
                        .buttonStyle(.plain)
                } else {
                    Text("Codex")
                    .font(NotchType.readable(11, weight: .medium))
                    .foregroundStyle(NotchPalette.secondary)
                }
                Spacer()
                Text(activeSessionsLabel)
                    .font(NotchType.readable(11))
                    .foregroundStyle(NotchPalette.secondary)
            }
            if let issue = appState.navigationIssue {
                Text(issue)
                    .font(NotchType.readable(11))
                    .foregroundStyle(NotchPalette.orange)
                    .lineLimit(2)
            }
            if liveSessionsForDisplay.isEmpty {
                Text("Waiting for local Codex activity.")
                    .font(NotchType.readable(11))
                    .foregroundStyle(NotchPalette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if contentMode == .expanded || contentMode == .attention {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(liveListEntries) { entry in
                            switch entry {
                            case let .project(label, count):
                                liveProjectHeader(label, sessionCount: count,
                                                  showsCount: liveProjectGroups.count > 1)
                            case let .session(session):
                                liveSessionRow(session)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.visible)
                .scrollPosition(id: $scrollAnchorSessionID, anchor: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(appState.activeSessions.count) active Codex sessions")
            } else {
                VStack(spacing: 0) {
                    liveProjectHeader(appState.presentation.snapshot.projectLabel, sessionCount: 1,
                                      showsCount: false)
                    liveSessionRow(appState.presentation.snapshot)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var liveSessionsForDisplay: [ActivitySnapshot] {
        if !appState.activeSessions.isEmpty { return appState.activeSessions }
        let focused = appState.presentation.snapshot
        return focused.sessionID.isEmpty ? [] : [focused]
    }

    private var activeSessionsLabel: String {
        let count = appState.activeSessions.count
        return count == 1 ? "1 active session" : "\(count) active sessions"
    }

    private enum LiveListEntry: Identifiable {
        case project(String, Int)
        case session(ActivitySnapshot)

        var id: String {
            switch self {
            case let .project(label, _): "project:\(label)"
            case let .session(session): session.sessionID
            }
        }
    }

    private var liveProjectGroups: [ActivityProjectGroup] {
        ActivityProjectGroups.make(from: liveSessionsForDisplay)
    }

    private var liveListEntries: [LiveListEntry] {
        liveProjectGroups.flatMap { group in
            [.project(group.label, group.sessions.count)] + group.sessions.map(LiveListEntry.session)
        }
    }

    private func liveProjectHeader(_ label: String, sessionCount: Int, showsCount: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "folder.fill")
                .font(NotchType.readable(10))
                .foregroundStyle(NotchPalette.secondary)
            Text(label == "Codex" ? "Unknown project" : label)
                .font(NotchType.readable(12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsCount && sessionCount > 1 {
                Text("\(sessionCount) sessions")
                    .font(NotchType.readable(10))
                    .foregroundStyle(NotchPalette.muted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }

    private func liveSessionRow(_ session: ActivitySnapshot) -> some View {
        let title = appState.sessionTitles[session.sessionID]
        return Button { appState.openLiveSession(session.sessionID) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(title ?? sessionLabel(for: session))
                    .font(title == nil ? NotchType.code(11) : NotchType.readable(12, weight: .medium))
                    .foregroundStyle(title == nil ? NotchPalette.secondary : .white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Label(livePhaseTitle(session.phase), systemImage: session.phase.symbol)
                        .font(NotchType.readable(11))
                        .foregroundStyle(accent(for: session.phase))
                        .lineLimit(1)
                    if let tool = session.currentTool {
                        Text(tool.summary)
                            .font(NotchType.readable(11))
                            .foregroundStyle(NotchPalette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 122, alignment: .trailing)
            }
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(tone: .row))
        .disabled(!session.phase.isActive || appState.isOpeningHost)
        .accessibilityHint("Open this chat in Codex Desktop.")
        .accessibilityLabel("\(session.projectLabel), \(title ?? sessionLabel(for: session)), \(livePhaseTitle(session.phase))\(session.currentTool.map { ", \($0.summary)" } ?? "")")
        .accessibilityAddTraits(appState.selectedLiveSessionID == session.sessionID ? .isSelected : [])
    }

    private func sessionLabel(for session: ActivitySnapshot) -> String {
        let identifiers = liveSessionsForDisplay.map(\.sessionID)
        let scalars = Array(session.sessionID)
        var length = min(8, scalars.count)
        while length < scalars.count {
            let candidate = String(scalars.prefix(length))
            let collisions = identifiers.filter { String($0.prefix(length)) == candidate }.count
            if collisions <= 1 { break }
            length += 1
        }
        return "Session \(String(scalars.prefix(length)))"
    }

    private func livePhaseTitle(_ phase: SessionPhase) -> String {
        switch phase {
        case .toolUse: "Working"
        case .completed: "Turn finished"
        default: phase.title
        }
    }

    private func accent(for phase: SessionPhase) -> Color {
        switch phase {
        case .waitingPermission: NotchPalette.orange
        case .waitingInput: NotchPalette.cyan
        case .completed: NotchPalette.green
        case .failed: NotchPalette.red
        case .interrupted: NotchPalette.secondary
        default: NotchPalette.blue
        }
    }

    private var demoMonitor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if contentMode == .peek || contentMode == .expanded {
                    usageLimits
                }
                Spacer(minLength: 0)
                NotchBadge(title: "Demo")
            }
            Button { appState.openFocusedHost() } label: {
                HStack(alignment: .top, spacing: 12) {
                    mascot.scaleEffect(0.72).frame(width: 25, height: 28)
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(PlaygroundScenario.taskTitle)
                                    .font(NotchType.readable(14, weight: .medium)).lineLimit(1)
                                    .foregroundStyle(.white)
                                Spacer(minLength: 0)
                                NotchBadge(title: "Codex")
                                NotchBadge(title: appState.host.title)
                            }
                            if let issue = appState.navigationIssue {
                                Text(issue).font(NotchType.readable(11))
                                    .foregroundStyle(NotchPalette.orange).lineLimit(2)
                            } else {
                                Text(PlaygroundScenario.prompt)
                                    .font(NotchType.readable(12)).foregroundStyle(NotchPalette.secondary).lineLimit(1)
                                if phase == .toolUse {
                                    Text("Writing \(Text("middleware.ts").font(NotchType.code()))")
                                        .font(NotchType.readable(12)).foregroundStyle(accent).lineLimit(1)
                                } else {
                                    Label(phase.title, systemImage: phase.symbol)
                                        .font(NotchType.readable(12)).foregroundStyle(accent)
                                }
                            }
                        }
                        .id(phase)
                        .transition(NotchMotion.pageTransition(reduceMotion: reduceMotion))
                    }
                }
                // Keep Nudgie alive for its one-shot celebration while the text
                // dissolves between working/done/failure, as in the reference.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: phase)
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchButtonStyle(tone: .row))
            .disabled(appState.isOpeningHost)
            .accessibilityHint("Activate \(appState.host.title). This demo has no real session identity.")
            if contentMode == .expanded {
                Button { appState.openFocusedHost() } label: {
                    HStack {
                        Text(appState.isOpeningHost ? "Opening…" : "Open in \(appState.host.title)")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(NotchType.readable(11)).foregroundStyle(NotchPalette.secondary)
                    .padding(.leading, 41)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotchButtonStyle(tone: .row))
                .disabled(appState.isOpeningHost)
                .accessibilityLabel("Open \(appState.host.title)")
                .transition(NotchMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
    }

    private var usageLimits: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(NotchType.readable(10))
                .foregroundStyle(NotchPalette.orange)
                .accessibilityHidden(true)
            if isDemo {
                usageWindow(PlaygroundScenario.fiveHourUsage)
                usageSeparator
                usageWindow(PlaygroundScenario.weeklyUsage)
            } else if let usage = appState.codexUsage {
                liveUsageWindow("5h", window: usage.fiveHour)
                usageSeparator
                liveUsageWindow("7d", window: usage.weekly)
            } else {
                unavailableUsageWindow("5h")
                usageSeparator
                unavailableUsageWindow("7d")
            }
        }
        .font(NotchType.readable(11))
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .help(usageHelpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usageAccessibilityText)
    }

    private var usageSeparator: some View {
        Rectangle()
            .fill(NotchPalette.muted)
            .frame(width: 1, height: 10)
            .accessibilityHidden(true)
    }

    private var usageHelpText: String {
        if isDemo { return "Demo usage: percentage used · time until reset" }
        if appState.codexUsage != nil { return "Live Codex usage: percentage used · time until reset" }
        if appState.isCodexUsageLoading { return "Loading Codex usage…" }
        if appState.isCodexUsageUnavailable { return "Codex usage is unavailable. Check your Codex sign-in." }
        return "Codex usage loads while the monitor is open."
    }

    private var usageAccessibilityText: String {
        if isDemo {
            return "Demo usage. 5-hour window: \(PlaygroundScenario.fiveHourUsage.usedPercent) percent used, resets in \(PlaygroundScenario.fiveHourUsage.accessibilityReset). Weekly window: \(PlaygroundScenario.weeklyUsage.usedPercent) percent used, resets in \(PlaygroundScenario.weeklyUsage.accessibilityReset)."
        }
        guard let usage = appState.codexUsage else {
            if appState.isCodexUsageLoading { return "Loading Codex usage." }
            if appState.isCodexUsageUnavailable { return "Codex usage unavailable. Check your Codex sign-in." }
            return "Codex usage loads while the monitor is open."
        }
        let fiveHourReset = usage.fiveHour.resetsAt.formatted(date: .omitted, time: .shortened)
        let weeklyReset = usage.weekly.resetsAt.formatted(date: .omitted, time: .shortened)
        return "Codex usage. 5-hour window: \(usage.fiveHour.usedPercent) percent used, resets at \(fiveHourReset). Weekly window: \(usage.weekly.usedPercent) percent used, resets at \(weeklyReset)."
    }

    private func usageWindow(_ window: PlaygroundScenario.UsageWindow) -> some View {
        HStack(spacing: 4) {
            Text(window.label).foregroundStyle(.white.opacity(0.90))
            Text("\(window.usedPercent)%")
                .fontWeight(.medium)
                .foregroundStyle(NotchPalette.green)
            Text(window.resetIn).foregroundStyle(NotchPalette.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Demo \(window.accessibilityName): \(window.usedPercent) percent used, resets in \(window.accessibilityReset)")
    }

    private func liveUsageWindow(_ label: String, window: CodexUsageWindow) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.white.opacity(0.90))
            Text("\(window.usedPercent)%")
                .fontWeight(.medium)
                .foregroundStyle(NotchPalette.green)
            Text(window.resetsAt, style: .relative)
                .foregroundStyle(NotchPalette.secondary)
        }
    }

    private func unavailableUsageWindow(_ label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.white.opacity(0.72))
            Text("—").foregroundStyle(NotchPalette.secondary)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            attentionTitle("Permission request", symbol: "circle.fill", color: NotchPalette.orange, secondaryTitle: true)
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(NotchPalette.orange)
                Text("Edit").foregroundStyle(NotchPalette.orange)
                Text(PlaygroundScenario.filePath).foregroundStyle(.white.opacity(0.90)).lineLimit(1).truncationMode(.middle)
            }
            .font(NotchType.code())
            VStack(spacing: 0) {
                ForEach(PlaygroundScenario.diff) { line in
                    HStack(spacing: 6) {
                        Text(line.number).foregroundStyle(NotchPalette.muted).frame(width: 20, alignment: .trailing)
                        Text(line.marker).frame(width: 10)
                        Text(line.code).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(NotchType.code(11))
                    .foregroundStyle(diffColor(line.kind))
                    .padding(.horizontal, 9)
                    .frame(height: 15)
                    .background {
                        Rectangle().fill(diffColor(line.kind).opacity(line.kind == .context ? 0 : 0.08))
                    }
                }
            }
            .background(Color(white: 0.035), in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Demo diff: remove one verification call, add a missing-token check and return verification")
            Text("+3 −1").font(NotchType.code(11)).foregroundStyle(NotchPalette.secondary)
            HStack(spacing: 8) {
                decisionButton("Deny", shortcut: "N", tone: .neutral) {
                    appState.resolvePreview(.init(label: "Denied", kind: .denied))
                }
                .keyboardShortcut("n")
                decisionButton("Allow once", shortcut: "Y", tone: .primary) {
                    appState.resolvePreview(.init(label: "Allowed once", kind: .allowed))
                }
                .keyboardShortcut("y")
            }
            .padding(.top, 2)
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 10) {
            attentionTitle("Codex asks", symbol: "bubble.left.fill", color: NotchPalette.cyan)
            Text(PlaygroundScenario.question).font(NotchType.readable(14, weight: .medium))
            VStack(spacing: 5) {
                ForEach(Array(PlaygroundScenario.options.enumerated()), id: \.offset) { index, option in
                    Button { appState.resolvePreview(.init(label: option, kind: .selected)) } label: {
                        HStack(spacing: 10) {
                            Text("⌘\(index + 1)")
                                .font(NotchType.readable(11, weight: .medium))
                                .foregroundStyle(NotchPalette.cyan)
                                .frame(width: 25, height: 24)
                                .background(NotchPalette.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            Text(option).font(NotchType.readable(13)).foregroundStyle(.white.opacity(0.92))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchButtonStyle(tone: .choice))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                    .accessibilityHint("Simulate selecting \(option). No answer is sent to Codex.")
                }
            }
        }
    }

    private func attentionTitle(_ title: String, symbol: String, color: Color, secondaryTitle: Bool = false) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
                .font(NotchType.readable(secondaryTitle ? 7 : 12))
            Text(title).foregroundStyle(secondaryTitle ? NotchPalette.secondary : color)
            Spacer()
            NotchBadge(title: "Demo")
        }
        .font(NotchType.readable(12, weight: secondaryTitle ? .regular : .medium))
    }

    private func decisionButton(_ title: String, shortcut: String, tone: NotchButtonStyle.Tone,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).font(NotchType.readable(12, weight: .medium))
                Text("⌘\(shortcut)").font(NotchType.readable(10)).opacity(0.55)
            }
            .foregroundStyle(tone == .primary ? Color.black : Color.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(tone: tone))
        .accessibilityHint("Simulated preview only. No permission decision is sent to Codex.")
    }

    private func confirmation(_ feedback: InteractionFeedback) -> some View {
        HStack(spacing: 9) {
            Image(systemName: feedback.kind == .denied ? "xmark" : "checkmark")
            Text(feedback.label)
        }
        .font(NotchType.readable(15, weight: .medium))
        .foregroundStyle(feedback.kind == .denied ? NotchPalette.orange : NotchPalette.green)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo: \(feedback.label)")
    }

    private func diffColor(_ kind: PlaygroundScenario.DiffLine.Kind) -> Color {
        switch kind {
        case .context: NotchPalette.secondary
        case .removed: NotchPalette.red
        case .added: NotchPalette.green
        }
    }

    private var accent: Color {
        switch phase {
        case .waitingPermission: NotchPalette.orange
        case .waitingInput: NotchPalette.cyan
        case .completed: NotchPalette.green
        case .failed: NotchPalette.red
        case .interrupted, .ended, .idle, .discovered: NotchPalette.secondary
        default: NotchPalette.blue
        }
    }
}

struct NotchShell: Shape {
    let attachedToScreenEdge: Bool
    let compactWidth: CGFloat
    let neckHeight: CGFloat
    var expansion: CGFloat

    init(attachedToScreenEdge: Bool, compactWidth: CGFloat, neckHeight: CGFloat, fullWidth: Bool = false) {
        self.attachedToScreenEdge = attachedToScreenEdge
        self.compactWidth = compactWidth
        self.neckHeight = neckHeight
        expansion = fullWidth ? 1 : 0
    }

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard attachedToScreenEdge else {
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
        }
        // Both states share the screen-edge anchor; expanded has a full-width top without a stepped neck.
        let width = rect.width
        let headLeft = rect.midX - width / 2
        let headRight = rect.midX + width / 2
        let shoulder = min(12, min(width / 4, rect.height / 4))
        let left = headLeft + shoulder
        let right = headRight - shoulder
        let top = rect.minY
        let bottom = rect.maxY
        let radius = min(10 + 8 * min(1, max(0, expansion)),
                         min((right - left) / 2, (rect.height - shoulder) / 2))
        let curve: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: headLeft, y: top))
        path.addLine(to: CGPoint(x: headRight, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + shoulder),
                      control1: CGPoint(x: right + shoulder * (1 - curve), y: top),
                      control2: CGPoint(x: right, y: top + shoulder * (1 - curve)))
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + shoulder))
        path.addCurve(to: CGPoint(x: headLeft, y: top),
                      control1: CGPoint(x: left, y: top + shoulder * (1 - curve)),
                      control2: CGPoint(x: left - shoulder * (1 - curve), y: top))
        path.closeSubpath()
        return path
    }
}
