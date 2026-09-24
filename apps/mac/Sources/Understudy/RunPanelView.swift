import SwiftUI
import UnderstudyCore

/// Run a skill from the Skills page, and follow it: each step's status and evidence, and the
/// buttons for a step that waits for the person (Approve, Skip) or to stop the run.
struct RunPanelView: View {
    @ObservedObject var runner: RunController
    @ObservedObject var ui: WorkspaceState
    let skill: Skill

    /// What the person typed for each placeholder, or its default.
    private var values: [String: String] {
        Dictionary(uniqueKeysWithValues: skill.variables.map { ($0, ui.runValues["\(skill.id)|\($0)"] ?? skill.defaultValues[$0] ?? "") })
    }
    var openReceipts: () -> Void

    private var showsThisSkill: Bool { runner.skill?.id == skill.id && !runner.results.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run \(skill.name)").font(.system(size: 20, weight: .semibold))
            Text("Understudy opens the apps and repeats your steps with the keyboard and by button names. It doesn't move the mouse. Steps that send, pay, or delete wait for your OK. Click the notch to stop.")
                .font(.system(size: 13)).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
            if let problem = runner.problem {
                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Values for the skill's {name} placeholders, prefilled with their defaults.
            ForEach(skill.variables, id: \.self) { name in
                HStack {
                    Text("{\(name)}").font(.system(.callout, design: .monospaced)).frame(width: 140, alignment: .leading)
                    TextField(name, text: Binding(get: { ui.runValues["\(skill.id)|\(name)"] ?? skill.defaultValues[name] ?? "" },
                                                  set: { ui.runValues["\(skill.id)|\(name)"] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
            }
            HStack(spacing: 12) {
                Button { runner.start(skill, mode: .run, values: values) } label: { Label("Run now", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(runner.isRunning)
                Button { runner.start(skill, mode: .stepByStep, values: values) } label: { Label("Test step by step", systemImage: "forward.frame") }
                    .disabled(runner.isRunning)
                if runner.isRunning && runner.skill?.id == skill.id {
                    Button("Stop", role: .destructive) { runner.stop() }
                }
            }
            if showsThisSkill {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(runner.steps.enumerated()), id: \.element.id) { index, step in
                        let result = runner.results[index]
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Self.symbol(result.status, active: index == runner.current))
                                .foregroundStyle(result.status == .done ? Color.accentColor : result.status == .notRun ? Color.secondary : Color.orange)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.intent).font(.system(size: 13, weight: index == runner.current ? .semibold : .regular))
                                if result.status != .notRun {
                                    Text("\(RunController.status(result.status)) · \(RunController.evidence(result))")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                if let pause = runner.pause, let index = runner.current {
                    HStack(spacing: 12) {
                        Text(pause == .approval ? "“\(runner.steps[index].intent)” needs your OK." : "Ready for step \(index + 1)?")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button("Skip step") { runner.skip() }
                        Button(pause == .approval ? "Approve" : "Run this step") { runner.approve() }.buttonStyle(.borderedProminent)
                    }.padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                if !runner.isRunning, runner.lastReceipt != nil {
                    Button("See the receipt", action: openReceipts)
                }
            }
        }
    }

    private static func symbol(_ status: StepOutcome.Status, active: Bool) -> String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .skipped: "arrow.uturn.forward.circle"
        case .blocked, .failed: "exclamationmark.circle.fill"
        case .notRun: active ? "circle.dotted" : "circle"
        }
    }
}
