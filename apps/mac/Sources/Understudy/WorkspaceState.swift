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

    // MARK: Editing steps (the Teach review and Edit skill)

    static func deleteStep(at index: Int, in steps: inout [SkillDefinition.Step]) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
    }

    static func moveStepUp(at index: Int, in steps: inout [SkillDefinition.Step]) {
        guard index > 0, steps.indices.contains(index) else { return }
        steps.swapAt(index, index - 1)
    }

    /// Changes what a "Type" step types.
    static func setTypedText(_ text: String, at index: Int, in steps: inout [SkillDefinition.Step]) {
        guard steps.indices.contains(index), steps[index].parameters["action"] == "type" else { return }
        steps[index].parameters["text"] = text
        steps[index].intent = "Type \(RecordedAction.quote(text))"
    }

    func deleteStep(at index: Int) { Self.deleteStep(at: index, in: &draftSteps) }
    func moveStepUp(at index: Int) { Self.moveStepUp(at: index, in: &draftSteps) }
    func setTypedText(_ text: String, at index: Int) { Self.setTypedText(text, at: index, in: &draftSteps) }

    // MARK: Edit skill

    /// The skill being edited on the Skills page, and its unsaved changes.
    @Published private(set) var editing: UUID?
    @Published var editName = ""
    @Published var editClient = ""
    @Published var editNotes = ""
    @Published var editSteps: [SkillDefinition.Step] = []

    func beginEdit(_ skill: Skill) {
        editing = skill.id
        editName = skill.name; editClient = skill.client
        editNotes = skill.rules; editSteps = skill.definition.steps
    }

    func cancelEdit() { editing = nil }

    var canSaveEdit: Bool {
        !editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !editClient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The skill with the edits applied. Its schedule and recording link stay as they were.
    func edited(_ skill: Skill) -> Skill {
        var updated = skill
        updated.name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.client = editClient.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.definition.rules = SkillDefinition.Rule.lines(editNotes)
        updated.definition.steps = editSteps
        return updated
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
