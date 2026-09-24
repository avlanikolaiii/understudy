import Foundation
import UnderstudyCore

/// Runs a skill on this Mac, one run at a time: it drives the RunEngine, shows progress in the
/// notch and the main window, and saves the receipt when the run ends.
@MainActor
final class RunController: ObservableObject {
    @Published private(set) var skill: Skill?
    @Published private(set) var mode: RunEngine.Mode = .run
    @Published private(set) var current: Int?
    @Published private(set) var pause: RunEngine.Pause?
    @Published private(set) var results: [StepOutcome] = []
    /// Why a run couldn't start, in words the person can act on.
    @Published private(set) var problem: String?
    /// The receipt of the last run that ended.
    @Published private(set) var lastReceipt: UUID?
    /// Called with each new run receipt, so the Receipts page shows it.
    var onReceipt: (UUID) -> Void = { _ in }

    private let library: SkillLibrary
    private let activity: NotchActivity
    private let performer: StepPerformer
    private let wait: (Double, @escaping () -> Void) -> Void
    private let ready: () -> String?
    private var engine: RunEngine?

    /// `ready` returns why runs can't happen now (e.g. no Accessibility access), or nil.
    init(library: SkillLibrary, activity: NotchActivity, performer: StepPerformer, ready: @escaping () -> String?,
         wait: @escaping (Double, @escaping () -> Void) -> Void = { seconds, then in
             DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: then)
         }) {
        self.library = library; self.activity = activity; self.performer = performer; self.ready = ready; self.wait = wait
    }

    var isRunning: Bool { engine.map { !$0.isFinished } ?? false }
    var steps: [SkillDefinition.Step] { engine?.steps ?? [] }

    /// Starts `skill`. Returns false, with `problem` set, if it can't run now.
    @discardableResult
    func start(_ skill: Skill, mode: RunEngine.Mode) -> Bool {
        problem = nil
        guard !isRunning else { problem = "\(self.skill?.name ?? "Another skill") is running. Stop it first."; return false }
        guard !skill.definition.steps.isEmpty else { problem = "\(skill.name) has no steps to run."; return false }
        if let reason = ready() { problem = reason; return false }
        self.skill = skill
        self.mode = mode
        let record = library.recorder(for: skill)
        let engine = RunEngine(steps: skill.definition.steps, mode: mode, performer: performer, wait: wait) { [weak self] event in
            self?.handle(event, record: record)
        }
        self.engine = engine
        results = engine.results
        engine.start()
        return true
    }

    func approve() { engine?.approve() }
    func skip() { engine?.skip() }
    func stop() { engine?.cancel() }

    private func handle(_ event: RunEngine.Event, record: (Receipt) -> Receipt) {
        guard let engine, let skill else { return }
        results = engine.results
        current = engine.current
        pause = engine.pause
        if case .ended(let outcome) = event {
            let receipt = record(Self.receipt(for: skill, engine: engine, outcome: outcome))
            current = nil
            lastReceipt = receipt.id
            onReceipt(receipt.id)
            activity.showRunReceipt(receipt)
            return
        }
        activity.showRun(skill.name, steps: engine.steps, results: engine.results, current: engine.current, pause: engine.pause)
    }

    /// The receipt of a finished run: each step's status and its evidence, kept apart.
    static func receipt(for skill: Skill, engine: RunEngine, outcome: RunEngine.Outcome) -> Receipt {
        let steps = zip(engine.steps, engine.results).map { step, result in
            ReceiptStep(step: step.intent, status: status(result.status), evidence: evidence(result))
        }
        let text: String
        switch outcome {
        case .completed: text = "Completed"
        case .blocked: text = "Blocked · needs you"
        case .cancelled: text = "Stopped"
        }
        let report = (["\(skill.name) · \(text)"] + steps.enumerated().map { "\($0.offset + 1). \($0.element.step): \($0.element.status). \($0.element.evidence)" })
            .joined(separator: "\n")
        return Receipt(skillName: skill.name, client: skill.client, missingSpend: false, report: report,
                       rules: skill.rules, ranSteps: steps, outcome: text)
    }

    static func status(_ status: StepOutcome.Status) -> String {
        switch status {
        case .done: "Done"
        case .skipped: "Skipped"
        case .blocked: "Blocked · needs you"
        case .failed: "Failed"
        case .notRun: "Not run"
        }
    }

    static func evidence(_ result: StepOutcome) -> String {
        switch result.evidence {
        case .verified: "Verified: \(result.detail)"
        case .notVerifiable: "Not verifiable: \(result.detail)"
        case .none: result.detail
        }
    }
}

/// Stands in for `AppPerformer` in the self-test: every step succeeds unless told otherwise.
@MainActor
final class ScriptedPerformer: StepPerformer {
    /// When set, the next step fails with this detail.
    var failNext: String?
    private(set) var performed: [String] = []

    func perform(_ step: SkillDefinition.Step, done: @escaping (StepOutcome) -> Void) {
        performed.append(step.id)
        let failure = failNext
        failNext = nil
        // A step takes a moment, as a real one does, so a run can be seen in progress.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            done(failure.map { StepOutcome(.failed, .none, $0) } ?? StepOutcome(.done, .verified, "Scripted"))
        }
    }

    func cancel() {}
}
