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
        if replacing != nil { return finishReplacing(watch) }
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
    /// Default values of the skill's `{name}` placeholders.
    @Published var editDefaults: [String: String] = [:]
    /// Values typed in the run panel, by skill and placeholder ("id|name").
    @Published var runValues: [String: String] = [:]

    func beginEdit(_ skill: Skill) {
        editing = skill.id
        editName = skill.name; editClient = skill.client
        editNotes = skill.rules; editSteps = skill.definition.steps
        editDefaults = skill.defaultValues
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
        // Placeholders keep their defaults as inputs the person is asked for ("ask").
        updated.definition.inputs = updated.definition.inputs.filter { $0.connector != "ask" }
            + Variables.names(in: editSteps).map { .init(id: $0, name: $0, connector: "ask", location: editDefaults[$0] ?? "") }
        return updated
    }

    // MARK: Adding a step by hand

    /// Where a new step goes: the Teach review ("review") or Edit skill ("edit"), before `index`.
    struct Insertion: Equatable { let list: String; let index: Int }

    @Published var adding: Insertion?
    @Published var addKind: ManualStep.Kind = .keys
    @Published var addText = ""
    @Published var addSeconds = 2
    /// The app a step acts on (bundle id), from the apps that are open.
    @Published var addApp = ""
    @Published var addAppName = ""
    @Published var addKeys = ""
    var addKeyCode: Int?

    func beginAdding(to list: String, at index: Int) {
        adding = Insertion(list: list, index: index)
        addText = ""; addKeys = ""; addKeyCode = nil; addSeconds = 2
    }

    /// The step the form describes, or nil while it's incomplete.
    var newStep: SkillDefinition.Step? {
        let text = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = addAppName.isEmpty ? nil : addAppName, bundle = addApp.isEmpty ? nil : addApp
        switch addKind {
        case .openApp: return bundle.map { ManualStep.openApp(name: addAppName, bundle: $0) }
        case .keys: return addKeys.isEmpty ? nil : ManualStep.keys(addKeys, keyCode: addKeyCode, app: app, bundle: bundle)
        case .type: return text.isEmpty ? nil : ManualStep.type(addText, app: app, bundle: bundle)
        case .waitText: return text.isEmpty ? nil : ManualStep.waitText(text, app: app, bundle: bundle)
        case .waitSeconds: return addSeconds > 0 ? ManualStep.waitSeconds(addSeconds) : nil
        case .openLink: return text.isEmpty ? nil : ManualStep.openLink(text)
        }
    }

    func finishAdding() {
        guard let adding, let step = newStep else { return }
        if adding.list == "review" { draftSteps.insert(step, at: min(adding.index, draftSteps.count)) }
        else { editSteps.insert(step, at: min(adding.index, editSteps.count)) }
        self.adding = nil
    }

    // MARK: Re-recording one step

    /// While set, the next take replaces this step of the skill being edited.
    @Published private(set) var replacing: Insertion?

    func rerecordStep(_ index: Int, of skill: Skill, watch: WatchSession) {
        guard editing == skill.id, editSteps.indices.contains(index), !watch.isWatching, watch.phase != .starting else { return }
        // A stopped take left open is already saved on disk; close it to record this step.
        if watch.isPresented { watch.dismiss() }
        replacing = Insertion(list: "edit", index: index)
        page = .teach
        teachingStep = 1
        watch.start()
        if !watch.isWatching && watch.phase != .starting { replacing = nil; page = .skills }   // it couldn't start: say why there
    }

    /// Ends a take started by "Record this step": its steps replace that step.
    private func finishReplacing(_ watch: WatchSession) {
        guard let target = replacing else { return }
        watch.stop()
        if let recording = watch.recording, !recording.actions.isEmpty, editSteps.indices.contains(target.index) {
            editSteps.replaceSubrange(target.index...target.index, with: StepsFromRecording.steps(from: recording))
        }
        replacing = nil
        watch.dismiss()
        teachingStep = 0
        page = .skills
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
