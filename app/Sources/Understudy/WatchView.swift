import SwiftUI

struct WatchPulse: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !active || reduceMotion)) { context in
            let glow = active && !reduceMotion
                ? 0.55 + 0.45 * (sin(context.date.timeIntervalSinceReferenceDate * .pi * 2) + 1) / 2
                : 1.0
            Circle().fill(Theme.ghostLight).frame(width: 8, height: 8)
                .opacity(glow).shadow(color: Theme.ghostLight.opacity(active ? glow : 0.3), radius: 5)
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

struct WatchView: View {
    @ObservedObject var session: WatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WatchPulse(active: session.isPlaying)
                Text(session.isPlaying ? "Watching sample" : session.phase == .finished ? "Replay complete" : "Replay stopped")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusTag(text: "Simulated")
                Text(session.clockText).monospacedDigit().font(.system(size: 13, weight: .medium))
                    .accessibilityLabel("Elapsed time \(session.elapsedSeconds) seconds")
            }
            Text("Weekly client update · Norte Studio")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
            Text("Predefined replay. No screen recording or app access. Nothing is learned, written, or sent.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 13) {
                ForEach(WatchSession.steps) { step in
                    let done = step.id < session.completedSteps
                    let current = step.id == session.completedSteps && session.isPlaying
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: done ? "checkmark.circle.fill" : current ? "circle.inset.filled" : "circle")
                            .foregroundStyle(done || current ? Theme.ghostLight : Theme.muted)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.system(size: 12, weight: current ? .semibold : .regular))
                            Text(step.detail).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(done ? "Replayed" : current ? "Replaying" : "Not replayed")
                }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 7) {
                Text("RULES FOR THIS DEMO").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                HStack {
                    TextField("Type a rule…", text: $session.ruleDraft)
                        .textFieldStyle(.roundedBorder).onSubmit { session.addRule() }
                        .accessibilityLabel("Type a rule")
                    Button("Add") { session.addRule() }.disabled(!session.canAddRule)
                }
                if !session.rules.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(session.rules.enumerated()), id: \.offset) { _, rule in
                                Text("• \(rule)").font(.system(size: 11)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(height: 52)
                }
                Text("Session notes only. Rules are not interpreted, enforced, or saved as a skill.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("\(session.completedSteps) of \(WatchSession.steps.count) steps replayed")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                if session.isPlaying {
                    Button("Stop", role: .destructive) { session.stop() }
                        .buttonStyle(WatchPrimaryButton(color: Theme.warn))
                } else {
                    Button("Replay") { session.start(keepingRules: true) }.buttonStyle(.bordered)
                    Button("Done") { session.dismiss() }
                        .buttonStyle(WatchPrimaryButton(color: Theme.ghostLight))
                }
            }
        }
    }
}

/// Keep the action legible even when the non-activating notch isn't the key window.
private struct WatchPrimaryButton: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black).padding(.horizontal, 13).padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 6))
    }
}
