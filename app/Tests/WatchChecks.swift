import Foundation

@main
struct WatchChecks {
    @MainActor
    static func main() {
        var time: TimeInterval = 100
        let session = WatchSession(now: { time })
        precondition(session.phase == .idle && !session.isPresented)
        session.start(automaticTicks: false)
        precondition(session.isPlaying && session.clockText == "00:00" && session.completedSteps == 0)
        session.ruleDraft = " \n "
        session.addRule()
        precondition(session.rules.isEmpty)
        session.ruleDraft = "  Never estimate missing spend.  "
        session.addRule()
        precondition(session.rules == ["Never estimate missing spend."] && session.ruleDraft.isEmpty)

        time += 4.9
        session.advance()
        precondition(session.completedSteps == 0 && session.elapsedSeconds == 4)
        time += 0.1
        session.advance()
        precondition(session.completedSteps == 1 && session.clockText == "00:05")
        session.ruleDraft = "Keep email as a draft."
        session.stop()
        precondition(session.phase == .stopped && session.rules.count == 2)
        time += 100
        session.advance()
        precondition(session.elapsedSeconds == 5 && session.completedSteps == 1)
        session.start(keepingRules: true, automaticTicks: false)
        precondition(session.elapsedSeconds == 0 && session.rules.count == 2)
        session.ruleDraft = "Review before sharing."
        time += 100
        session.advance()
        precondition(session.phase == .finished && session.completedSteps == WatchSession.steps.count)
        precondition(session.elapsedSeconds == session.duration && session.rules.count == 3)
        session.stop()
        precondition(session.phase == .finished)
        session.dismiss()
        precondition(!session.isPresented)
        session.start(automaticTicks: false)
        precondition(session.rules.isEmpty && session.ruleDraft.isEmpty && session.elapsedSeconds == 0)
        session.dismiss()
        time += 10
        session.advance()
        precondition(session.phase == .idle && session.elapsedSeconds == 0)

        // Exercise the actual Combine timer and its cancellation, not just manual ticks.
        let live = WatchSession()
        live.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        precondition(live.elapsedSeconds >= 1)
        live.stop()
        let stopped = live.elapsedSeconds
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        precondition(live.elapsedSeconds == stopped && live.phase == .stopped)
        print("PASS: step boundaries, timer, Stop, cancellation, completion, rule trimming, pending-rule retention, replay, and fresh-session reset")
    }
}
