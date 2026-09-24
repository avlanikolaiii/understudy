import SwiftUI
import UnderstudyCore

/// How a list of steps is edited: delete, move up, retype (by index).
struct StepEdits {
    let delete: (Int) -> Void
    let moveUp: (Int) -> Void
    let retype: (String, Int) -> Void
}

/// A skill's steps: what each does, in which app, how it runs, and what needs the person.
/// With `edits`, each step can be deleted, moved up, or (for typing) changed.
struct StepListView: View {
    let steps: [SkillDefinition.Step]
    var edits: StepEdits?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .frame(width: 22, height: 22).background(Color.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.intent).font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            Text(step.parameters["app"] ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(Self.how(step)).font(.caption).foregroundStyle(.secondary)
                            if step.effect.needsApproval {
                                Label("Needs your OK", systemImage: "hand.raised").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if step.executor == .unsupported, let reason = step.parameters["reason"] {
                            Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            if let bundle = step.parameters["reveal"] {
                                Button("Reopen \(step.parameters["app"] ?? "the app") for Understudy") {
                                    AX.reopenRevealed(bundle: bundle) { _ in }
                                }.controlSize(.small)
                            }
                        }
                        if let edits, step.parameters["action"] == "type" {
                            TextField("Text to type", text: Binding(get: { step.parameters["text"] ?? "" },
                                                                   set: { edits.retype($0, index) }))
                                .textFieldStyle(.roundedBorder).font(.caption).frame(maxWidth: 320)
                                .accessibilityLabel("Text for step \(index + 1)")
                        }
                    }
                    Spacer()
                    if let edits {
                        Button { edits.moveUp(index) } label: { Image(systemName: "arrow.up") }
                            .buttonStyle(.borderless).disabled(index == 0).help("Move up")
                            .accessibilityLabel("Move step \(index + 1) up")
                        Button(role: .destructive) { edits.delete(index) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete step")
                            .accessibilityLabel("Delete step \(index + 1)")
                    }
                }
                .padding(10).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    /// How the step runs, in a few words.
    static func how(_ step: SkillDefinition.Step) -> String {
        switch step.parameters["action"] {
        case "activate": "Opens the app"
        case "press": "Presses it by name"
        case "focus": "Clicks into the field"
        case "type": "Types with the keyboard"
        case "keys": "Presses keys"
        default: step.executor == .unsupported ? "Can't run yet" : ""
        }
    }
}
