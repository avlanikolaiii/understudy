import SwiftUI
import UnderstudyCore

/// Teach step 2: the same Watch the notch shows. What is recorded appears here as it happens.
struct WorkspaceWatchView: View {
    @ObservedObject var session: WatchSession
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(session.isWatching ? "Watching" : session.phase == .starting ? "Choose what to record"
                      : session.isPresented ? "Stopped" : "Watch",
                      systemImage: session.isWatching ? "record.circle" : "checklist")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(session.clockText).monospacedDigit()
                    .accessibilityLabel("Elapsed time \(session.elapsedSeconds) seconds")
            }
            Text(session.isPresented
                 ? "Do the task as you usually do. Understudy notes each app, button, and field you use. Stop with the button below or your shortcut."
                 : "Understudy records your screen and notes each app, button, and field you use, only while Watch runs. Recordings stay on this Mac. Passwords are never recorded.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let problem = session.problem {
                VStack(alignment: .leading, spacing: 8) {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if !AX.isTrusted {
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if session.actions.isEmpty {
                        Text(session.isWatching ? "Nothing yet. Switch to the app you use for this task."
                             : "Recorded steps appear here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    // The latest steps; the full log is saved with the recording.
                    ForEach(Array(session.actions.enumerated().suffix(8)), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: Self.symbol(action.kind)).foregroundStyle(Color.accentColor).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.summary)
                                Text([action.app, action.window].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%d:%02d", Int(action.t) / 60, Int(action.t) % 60))
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.isPresented {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes for this skill").font(.headline)
                    HStack {
                        TextField("Add a rule or a reminder", text: $session.ruleDraft)
                            .textFieldStyle(.roundedBorder).onSubmit { session.addRule() }
                            .accessibilityLabel("Watch note")
                        Button("Add") { session.addRule() }.disabled(!session.canAddRule)
                    }
                    ForEach(Array(session.rules.enumerated()), id: \.offset) { _, rule in
                        Label(rule, systemImage: "text.bubble").font(.callout).textSelection(.enabled)
                    }
                }
            }
            HStack {
                Text("\(session.actions.count) steps recorded").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if session.isWatching {
                    Button("Stop Watch", role: .destructive) { session.stop() }
                        .buttonStyle(.borderedProminent)
                } else if session.isPresented {
                    Button("Record again") { session.start(keepingRules: true) }
                    Button("Review", action: onReview).buttonStyle(.borderedProminent)
                } else {
                    Button("Start Watch") { session.start() }.buttonStyle(.borderedProminent)
                        .disabled(session.phase == .starting)
                }
            }
        }
    }

    private static func symbol(_ kind: RecordedAction.Kind) -> String {
        switch kind {
        case .appSwitch: "macwindow"
        case .click: "cursorarrow.click"
        case .typing: "keyboard"
        case .shortcut: "command"
        case .selection: "tablecells"
        }
    }
}
