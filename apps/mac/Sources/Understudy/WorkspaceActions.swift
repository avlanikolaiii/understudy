import Foundation
import UnderstudyCore

/// Button actions that touch the library and the notch. They live here, not in the view,
/// so the main window and the self-test run exactly the same code.
@MainActor
extension WorkspaceState {
    var canSaveSkill: Bool {
        !skillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The skill the Skills page acts on: the selected one if it still exists, else the first.
    func activeSkill(in library: SkillLibrary) -> Skill {
        library.skills.first(where: { $0.id == selectedSkill?.id }) ?? library.skills.first ?? .sample
    }

    /// "Save skill" on the Review step: the reviewed steps, the notes, and the recording they came from.
    func saveReviewedSkill(library: SkillLibrary, watch: WatchSession, activity: NotchActivity) {
        let definition = draftSteps.isEmpty ? SkillDefinition.prepared(notes: rules)
            : SkillDefinition(steps: draftSteps, rules: SkillDefinition.Rule.lines(rules), recording: draftRecording)
        let skill = Skill(name: skillName.trimmingCharacters(in: .whitespacesAndNewlines),
                          client: clientName.trimmingCharacters(in: .whitespacesAndNewlines), definition: definition)
        library.save(skill) { [weak self] saved in self?.selectedSkill = saved; activity.showLearned(saved) }
        watch.dismiss(); clearDraft(); teachingStep = 0; page = .skills
    }

    /// "Create steps from latest recording" on the Skills page, for a skill saved without steps.
    func addStepsFromLatestRecording(to skill: Skill, library: SkillLibrary, watch: WatchSession) {
        guard !skill.isSample, skill.definition.steps.isEmpty, let recording = watch.latestRecording() else { return }
        var updated = skill
        updated.definition = SkillDefinition(steps: StepsFromRecording.steps(from: recording),
                                             rules: skill.definition.rules, recording: recording.id)
        library.update(updated) { [weak self] saved in self?.selectedSkill = saved }
    }

    /// "Rehearse sample" on the Skills page.
    func rehearseActiveSkill(library: SkillLibrary, activity: NotchActivity) {
        let skill = activeSkill(in: library)
        activity.rehearse(skill, scenario: scenario, record: library.recorder(for: skill)) { [weak self] receipt in
            self?.selectedReceipt = receipt.id; self?.page = .results
        }
    }
}
