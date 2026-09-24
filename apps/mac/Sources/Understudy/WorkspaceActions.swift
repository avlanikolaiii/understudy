import Foundation

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

    /// "Save sample skill" on the Review step.
    func saveReviewedSkill(library: SkillLibrary, watch: WatchSession, activity: NotchActivity) {
        let skill = Skill(name: skillName.trimmingCharacters(in: .whitespacesAndNewlines),
                          client: clientName.trimmingCharacters(in: .whitespacesAndNewlines), rules: rules)
        library.save(skill) { [weak self] saved in self?.selectedSkill = saved; activity.showLearned(saved) }
        watch.dismiss(); teachingStep = 0; page = .skills
    }

    /// "Rehearse sample" on the Skills page.
    func rehearseActiveSkill(library: SkillLibrary, activity: NotchActivity) {
        let skill = activeSkill(in: library)
        activity.rehearse(skill, scenario: scenario, record: library.recorder(for: skill)) { [weak self] receipt in
            self?.selectedReceipt = receipt.id; self?.page = .results
        }
    }
}
