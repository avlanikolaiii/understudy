import Foundation
import UnderstudyCore

/// A performer that answers from a script, and remembers what it was asked to do.
@MainActor
final class FakePerformer: StepPerformer {
    var outcomes: [String: StepOutcome] = [:]
    var performed: [String] = []
    var cancelled = 0
    var holdNext = false
    var held: ((StepOutcome) -> Void)?

    func perform(_ step: SkillDefinition.Step, done: @escaping (StepOutcome) -> Void) {
        performed.append(step.id)
        if holdNext { holdNext = false; held = done; return }
        done(outcomes[step.id] ?? StepOutcome(.done, .verified, "ok"))
    }

    func cancel() { cancelled += 1 }
}

@main
struct RunChecks {
    @MainActor static func step(_ id: String, _ effect: SkillDefinition.Step.Effect = .write, unsupported: Bool = false, after: String = "0.5") -> SkillDefinition.Step {
        SkillDefinition.Step(id: id, intent: id, executor: unsupported ? .unsupported : .keyboard, effect: effect, evidence: .none,
                             parameters: ["after": after, "reason": "needs the mouse"])
    }

    @MainActor static func main() {
        var waits: [Double] = []
        let now: (Double, @escaping () -> Void) -> Void = { seconds, then in waits.append(seconds); then() }

        // A plain run: every step in order, waits from the recording, one result each, completed.
        var events: [RunEngine.Event] = []
        var performer = FakePerformer()
        var engine = RunEngine(steps: [step("a"), step("b", .read), step("c")], mode: .run, performer: performer, wait: now) { events.append($0) }
        engine.start()
        precondition(performer.performed == ["a", "b", "c"] && engine.outcome == .completed && waits == [0.5, 0.5, 0.5])
        precondition(engine.results.allSatisfy { $0.status == .done } && events.last == .ended(.completed))
        precondition(events.filter { if case .started = $0 { return true }; return false }.count == 3)

        // Sending waits for approval; nothing after it runs until then.
        performer = FakePerformer()
        engine = RunEngine(steps: [step("draft"), step("send", .send), step("after")], mode: .run, performer: performer, wait: now) { _ in }
        engine.start()
        precondition(performer.performed == ["draft"] && engine.pause == .approval && engine.current == 1 && engine.outcome == nil)
        engine.approve()
        precondition(performer.performed == ["draft", "send", "after"] && engine.outcome == .completed)

        // Skipping a paused step records it as skipped and goes on.
        performer = FakePerformer()
        engine = RunEngine(steps: [step("delete", .delete), step("next")], mode: .run, performer: performer, wait: now) { _ in }
        engine.start(); engine.skip()
        precondition(performer.performed == ["next"] && engine.results[0].status == .skipped && engine.outcome == .completed)

        // A step that can't run blocks the run: it isn't attempted and nothing after it runs.
        performer = FakePerformer()
        engine = RunEngine(steps: [step("a"), step("click", unsupported: true), step("b")], mode: .run, performer: performer, wait: now) { _ in }
        engine.start()
        precondition(performer.performed == ["a"] && engine.outcome == .blocked)
        precondition(engine.results[1].status == .blocked && engine.results[1].detail == "needs the mouse" && engine.results[2].status == .notRun)

        // A failure stops the run too.
        performer = FakePerformer()
        performer.outcomes["b"] = StepOutcome(.failed, .none, "Couldn't find “Send”.")
        engine = RunEngine(steps: [step("a"), step("b"), step("c")], mode: .run, performer: performer, wait: now) { _ in }
        engine.start()
        precondition(performer.performed == ["a", "b"] && engine.outcome == .blocked && engine.results[2].status == .notRun)

        // Step by step: each step waits for confirmation and runs without the recorded pause.
        waits = []
        performer = FakePerformer()
        engine = RunEngine(steps: [step("a"), step("b")], mode: .stepByStep, performer: performer, wait: now) { _ in }
        engine.start()
        precondition(performer.performed.isEmpty && engine.pause == .confirmation)
        engine.approve()
        precondition(performer.performed == ["a"] && engine.pause == .confirmation && engine.current == 1)
        engine.approve()
        precondition(engine.outcome == .completed && waits == [0, 0])

        // Stopping mid-step cancels it; a late answer from the cancelled step is ignored.
        performer = FakePerformer()
        performer.holdNext = true
        events = []
        engine = RunEngine(steps: [step("slow"), step("b")], mode: .run, performer: performer, wait: now) { events.append($0) }
        engine.start()
        engine.cancel()
        performer.held?(StepOutcome(.done, .verified, "late"))
        precondition(performer.cancelled == 1 && engine.outcome == .cancelled && performer.performed == ["slow"])
        precondition(engine.results[0].status == .notRun && events.last == .ended(.cancelled))
        engine.approve(); engine.skip(); engine.start(); engine.cancel()
        precondition(performer.performed == ["slow"] && events.filter { $0 == .ended(.cancelled) }.count == 1)

        // An empty skill completes at once.
        engine = RunEngine(steps: [], mode: .run, performer: FakePerformer(), wait: now) { _ in }
        engine.start()
        precondition(engine.outcome == .completed)
        print("PASS: ordered run with recorded pauses, approval, skip, unsupported and failed steps block, step by step, cancel with a late answer, empty skill")
    }
}
