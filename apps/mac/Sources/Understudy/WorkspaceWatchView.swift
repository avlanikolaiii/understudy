import SwiftUI

/// A native workspace presentation of the same session shown by the notch.
struct WorkspaceWatchView: View {
    @ObservedObject var session: WatchSession
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(session.isPlaying ? "Watching sample" : session.phase == .finished ? "Replay complete" : session.isPresented ? "Replay stopped" : "Watch demo",
                      systemImage: session.isPlaying ? "record.circle" : "checklist")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("Simulated").font(.callout).foregroundStyle(.secondary)
                Text(session.clockText).monospacedDigit()
                    .accessibilityLabel("Elapsed time \(session.elapsedSeconds) seconds")
            }
            Text("Weekly client update · Norte Studio\nPredefined example. No screen recording, app access, or AI learning.")
                .font(.callout).foregroundStyle(.secondary)
            ProgressView(value: Double(session.completedSteps), total: Double(WatchSession.steps.count))
                .accessibilityLabel("Demo progress")
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(WatchSession.steps) { step in
                        let done = step.id < session.completedSteps
                        let active = session.isPlaying && step.id == session.completedSteps
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle")
                                .foregroundStyle(done || active ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).fontWeight(active ? .semibold : .regular)
                                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(done ? "Replayed" : active ? "Replaying" : "Not replayed")
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
                    Text("Notes carry into sample-skill review. They are not interpreted or enforced.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(session.completedSteps) of \(WatchSession.steps.count) steps replayed")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if session.isPlaying {
                    Button("Stop Watch", role: .destructive) { session.stop() }
                        .buttonStyle(.borderedProminent)
                } else if session.isPresented {
                    Button("Replay") { session.start(keepingRules: true) }
                    Button("Review sample skill", action: onReview).buttonStyle(.borderedProminent)
                } else {
                    Button("Start Watch demo") { session.start() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
