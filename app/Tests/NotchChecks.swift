import Foundation

@main struct NotchChecks {
    @MainActor static func main() async {
        var time: TimeInterval = 0
        let watch = WatchSession(now: { time })
        // Row timing runs instantly; the receipt's 15 s display doesn't expire during the checks.
        let activity = NotchActivity(watch: watch, sleep: { s in
            if s < 5 { await Task.yield() } else { try? await Task.sleep(nanoseconds: 60_000_000_000) }
        })
        func settle() async { for _ in 0..<20 { await Task.yield(); RunLoop.main.run(until: Date().addingTimeInterval(0.005)) } }

        await settle()
        precondition(activity.mode == .idle)

        // Watching: the page's pulsing strip, rows in the order they happened, capped at 4.
        watch.start(automaticTicks: false)
        await settle()
        precondition(activity.mode == .watching && activity.dot == .pulse && activity.label == "Watching" && activity.meta == "0:00")
        time = 11; watch.advance()
        watch.ruleDraft = "If a number's missing, ask me first."; watch.addRule()
        await settle()
        precondition(activity.rows.map(\.app) == ["Numbers", "TextEdit", "Your rule"] && activity.rows.last?.tone == .said)
        time = 25; watch.advance()
        await settle()
        precondition(activity.rows.count == 4 && activity.meta == "0:25" && activity.mode == .stopped)
        precondition(activity.footer.contains("Simulated"))

        // Rehearsal: blue dot, read-only, then a receipt that says it isn't ready to send.
        var recorded: [Receipt] = []
        var finished: Receipt?
        activity.rehearse(.sample, scenario: .missing, record: { recorded.append($0); return $0 }) { finished = $0 }
        precondition(activity.mode == .rehearsing && activity.dot == .rehearse && activity.detail?.hasPrefix("Read-only") == true)
        await settle()
        precondition(recorded.count == 1 && finished?.missingSpend == true)
        precondition(activity.mode == .receipt && activity.detail == "Not ready to send")
        precondition(activity.rows.contains { $0.end == "needs you" && $0.endTone == .hold })

        // Dismissing returns to what Watch is doing; a new Watch always takes over.
        activity.dismiss()
        await settle()
        precondition(activity.mode == .stopped)
        watch.dismiss()
        await settle()
        precondition(activity.mode == .idle)
        activity.showLearned(Skill(name: "Weekly client update", client: "Norte Studio", rules: "a\nb"))
        precondition(activity.mode == .learned && activity.rows.last?.text == "2 saved with the skill")
        watch.start(automaticTicks: false)
        await settle()
        precondition(activity.mode == .watching && activity.rows.isEmpty)
        print("PASS: notch strip states for watching, row order and cap, read-only rehearsal, missing-spend receipt, and takeover")
    }
}
