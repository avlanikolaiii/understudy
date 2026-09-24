import Foundation

/// Performs one step of a skill. The app's implementation drives other apps; checks use a fake.
@MainActor
public protocol StepPerformer: AnyObject {
    /// Performs `step` and calls `done` once, with what happened and how it was checked.
    func perform(_ step: SkillDefinition.Step, done: @escaping (StepOutcome) -> Void)
    /// Stops a step in progress, if it can.
    func cancel()
}

/// What one step did (status) and how that was checked (evidence), kept separate.
public struct StepOutcome: Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case done, skipped, blocked, failed, notRun }
    public enum Evidence: String, Codable, Sendable { case verified, notVerifiable, none }

    public var status: Status
    public var evidence: Evidence
    /// In plain words: what was checked, or why it stopped.
    public var detail: String

    public init(_ status: Status, _ evidence: Evidence, _ detail: String) {
        self.status = status; self.evidence = evidence; self.detail = detail
    }
}

/// Runs a skill's steps in order, one at a time. Steps that send, pay, or delete wait for the
/// person's OK; in step-by-step mode every step does. A step that can't run, or fails, stops the
/// run: nothing after it is guessed. Every run ends with one result per step.
@MainActor
public final class RunEngine {
    public enum Mode: Equatable, Sendable { case run, stepByStep }
    public enum Outcome: String, Codable, Sendable { case completed, blocked, cancelled }
    /// Why the run is paused on a step.
    public enum Pause: Equatable, Sendable { case approval, confirmation }

    public enum Event: Equatable {
        case started(Int)
        case paused(Int, Pause)
        case finished(Int, StepOutcome)
        case ended(Outcome)
    }

    public let steps: [SkillDefinition.Step]
    public let mode: Mode
    public private(set) var results: [StepOutcome]
    public private(set) var outcome: Outcome?
    /// The step running or paused now.
    public private(set) var current: Int?
    public private(set) var pause: Pause?

    private let performer: StepPerformer
    private let wait: (Double, @escaping () -> Void) -> Void
    private let onEvent: (Event) -> Void
    /// Changes when the run moves on, so a late callback from a cancelled step is ignored.
    private var turn = 0

    /// `wait(seconds, then)` waits before a step (the pause from the recording).
    public init(steps: [SkillDefinition.Step], mode: Mode, performer: StepPerformer,
                wait: @escaping (Double, @escaping () -> Void) -> Void, onEvent: @escaping (Event) -> Void) {
        self.steps = steps; self.mode = mode; self.performer = performer; self.wait = wait; self.onEvent = onEvent
        results = steps.map { _ in StepOutcome(.notRun, .none, "Not run.") }
    }

    public var isFinished: Bool { outcome != nil }

    public func start() {
        guard current == nil, outcome == nil else { return }
        next(0)
    }

    /// Runs the paused step.
    public func approve() {
        guard let index = current, pause != nil, outcome == nil else { return }
        pause = nil
        perform(index)
    }

    /// Skips the paused step and moves on.
    public func skip() {
        guard let index = current, pause != nil, outcome == nil else { return }
        pause = nil
        finish(index, StepOutcome(.skipped, .none, "Skipped by you."))
    }

    /// Stops the run. The step in progress is cancelled; the rest are not run.
    public func cancel() {
        guard outcome == nil else { return }
        if current != nil, pause == nil { performer.cancel() }
        if let index = current { results[index] = StepOutcome(.notRun, .none, "Stopped by you before it finished.") }
        end(.cancelled)
    }

    // MARK: Private

    private func next(_ index: Int) {
        turn += 1
        guard index < steps.count else { return end(.completed) }
        current = index
        let step = steps[index]
        if step.executor == .unsupported {
            results[index] = StepOutcome(.blocked, .none, step.parameters["reason"] ?? "This step can't run yet.")
            onEvent(.finished(index, results[index]))
            return end(.blocked)
        }
        if step.effect.needsApproval || mode == .stepByStep {
            pause = step.effect.needsApproval ? .approval : .confirmation
            return onEvent(.paused(index, pause!))
        }
        perform(index)
    }

    private func perform(_ index: Int) {
        let step = steps[index], mine = turn
        onEvent(.started(index))
        let after = Double(step.parameters["after"] ?? "") ?? 0
        wait(mode == .stepByStep ? 0 : after) { [weak self] in
            guard let self, self.turn == mine, self.outcome == nil else { return }
            self.performer.perform(step) { [weak self] result in
                guard let self, self.turn == mine, self.outcome == nil else { return }
                self.finish(index, result)
            }
        }
    }

    private func finish(_ index: Int, _ result: StepOutcome) {
        results[index] = result
        onEvent(.finished(index, result))
        if result.status == .failed || result.status == .blocked { return end(.blocked) }
        next(index + 1)
    }

    private func end(_ outcome: Outcome) {
        turn += 1
        self.outcome = outcome
        pause = nil
        onEvent(.ended(outcome))
    }
}
