import Combine
import Foundation
import UnderstudyCore

enum PrototypePage: String, CaseIterable {
    case home = "Home", teach = "Teach a skill", skills = "Skills", results = "Receipts", account = "Account"
    static let workspace: [PrototypePage] = [.home, .teach, .skills, .results]
    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"; case .teach: "plus.circle"; case .skills: "square.stack.3d.up"
        case .results: "checkmark.rectangle"; case .account: "person.crop.circle"
        }
    }
}

/// Window navigation and draft state stay alive when the workspace is closed.
@MainActor
final class WorkspaceState: ObservableObject {
    @Published var page: PrototypePage? = .home
    @Published var teachingStep = 0
    @Published var skillName = "Weekly client update"
    @Published var clientName = "Norte Studio"
    @Published var rules = Skill.sample.rules
    @Published var selectedSkill: Skill?
    @Published var scenario: SampleCase = .complete
    @Published var selectedReceipt: UUID?
    /// The steps being reviewed, made from the latest recording. Edits here are saved with the skill.
    @Published var draftSteps: [SkillDefinition.Step] = []
    /// The recording `draftSteps` came from.
    private(set) var draftRecording: UUID?

    func showTeaching(watch: WatchSession) {
        page = .teach
        if watch.isPresented { teachingStep = 1 }
    }

    func startWatch(_ watch: WatchSession) {
        page = .teach
        teachingStep = 1
        if !watch.isPresented { watch.start() }
    }

    func reviewWatch(_ watch: WatchSession) {
        watch.stop()
        watch.addRule()
        // Copy demo notes once even when the user goes back and reviews again.
        var notes = rules.components(separatedBy: .newlines)
        for rule in watch.rules where !notes.contains(rule) { notes.append(rule) }
        rules = notes.filter { !$0.isEmpty }.joined(separator: "\n")
        // Make steps from a new recording; reviewing the same one again keeps the edits.
        if let recording = watch.recording, recording.id != draftRecording {
            draftSteps = StepsFromRecording.steps(from: recording)
            draftRecording = recording.id
        }
        teachingStep = 2
        page = .teach
    }

    // MARK: Editing the reviewed steps

    func deleteStep(at index: Int) {
        guard draftSteps.indices.contains(index) else { return }
        draftSteps.remove(at: index)
    }

    func moveStepUp(at index: Int) {
        guard index > 0, draftSteps.indices.contains(index) else { return }
        draftSteps.swapAt(index, index - 1)
    }

    /// Changes what a "Type" step types.
    func setTypedText(_ text: String, at index: Int) {
        guard draftSteps.indices.contains(index), draftSteps[index].parameters["action"] == "type" else { return }
        draftSteps[index].parameters["text"] = text
        draftSteps[index].intent = "Type \(RecordedAction.quote(text))"
    }

    // MARK: When a skill runs

    /// The trigger being edited on the Skills page, and whose it is.
    @Published var triggerDraft = SkillDefinition.Trigger.manual
    private(set) var triggerSkill: UUID?

    /// Starts editing `skill`'s trigger, unless it's already being edited.
    func editTrigger(of skill: Skill) {
        guard triggerSkill != skill.id else { return }
        triggerDraft = skill.definition.trigger
        triggerSkill = skill.id
    }

    func toggleWeekday(_ day: Int) {
        var days = Set(triggerDraft.weekdays ?? [])
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        triggerDraft.weekdays = days.sorted()
    }

    /// The draft as it will be saved: set on this Mac, with its summary, and times filled in.
    func finishedTrigger(device: String) -> SkillDefinition.Trigger {
        var trigger = triggerDraft
        if trigger.kind == .schedule { trigger.hour = trigger.hour ?? 9; trigger.minute = trigger.minute ?? 0 }
        if trigger.kind == .interval { trigger.everyHours = trigger.everyHours ?? 1 }
        trigger.device = trigger.kind == .manual ? nil : device
        trigger.detail = trigger.summary
        return trigger
    }

    func clearDraft() {
        draftSteps = []
        draftRecording = nil
    }
}
