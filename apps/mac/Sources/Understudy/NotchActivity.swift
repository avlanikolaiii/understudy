import Combine
import Foundation
import UnderstudyCore

/// One line in the notch strip: the app, what happened, and an optional status at the end.
struct NotchRow: Identifiable, Equatable {
    enum Tone: Equatable { case plain, said, ok, hold }
    let id: Int
    let app: String
    let text: String
    var tone: Tone = .plain
    var end: String?
    var endTone: Tone = .plain
}

/// What the notch shows. It follows the landing page's story: Watching → New skill →
/// Rehearsing (read-only) → Receipt. Watching shows what is really being recorded; the states
/// after it are still simulated and say so.
@MainActor
final class NotchActivity: ObservableObject {
    enum Mode: Equatable { case idle, watching, stopped, learned, rehearsing, scheduled, running, receipt, demo, menu }
    enum Dot: Equatable { case steady, pulse, rehearse }

    @Published private(set) var mode: Mode = .idle
    /// Short, so it fits beside the camera housing.
    @Published private(set) var label = ""
    /// A second line under the notch, for the longer part of the label.
    @Published private(set) var detail: String?
    @Published private(set) var meta = ""
    @Published private(set) var rows: [NotchRow] = []
    @Published private(set) var dot: Dot = .steady
    /// The honest label: "Simulated" or "Concept demonstration".
    @Published private(set) var footer = ""
    /// While a run waits for the person (an OK, or the next step when testing), which.
    @Published private(set) var runPause: RunEngine.Pause?

    private let watch: WatchSession
    private var bag = Set<AnyCancellable>()
    private var watchLog: [NotchRow] = []
    private var loggedActions = 0
    private var loggedRules = 0
    private var lastPhase: WatchSession.Phase = .idle
    private var overlayActive = false
    private var generation = 0
    private var nextID = 0
    private let sleep: (Double) async -> Void

    static let rowSeconds = 1.4

    init(watch: WatchSession, sleep: @escaping (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.watch = watch
        self.sleep = sleep
        Publishers.CombineLatest4(watch.$phase, watch.$elapsedSeconds, watch.$rules, watch.$actions)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.watchChanged() }
            .store(in: &bag)
    }

    var isRehearsing: Bool { mode == .rehearsing }

    /// Where a click on the strip should take the main window.
    var page: PrototypePage {
        switch mode {
        case .watching, .stopped: .teach
        case .learned: .skills
        case .running, .scheduled: .skills
        case .rehearsing, .receipt: .results
        case .idle, .demo, .menu: .home
        }
    }

    // MARK: Watch

    /// Shown under every Watch state: what is recorded, and where it stays.
    static let watchFooter = "Recording on this Mac · passwords are never recorded"

    func watchChanged() {
        let phase = watch.phase
        if phase == .watching && lastPhase != .watching {
            // A new recording always takes over the notch.
            cancelOverlay()
            watchLog = watch.rules.map { ruleRow($0) }
            loggedActions = 0
            loggedRules = watch.rules.count
        }
        while loggedActions < watch.actions.count {
            let action = watch.actions[loggedActions]
            watchLog.append(row(action.app, action.summary))
            loggedActions += 1
        }
        while loggedRules < watch.rules.count {
            watchLog.append(ruleRow(watch.rules[loggedRules]))
            loggedRules += 1
        }
        lastPhase = phase
        guard !overlayActive else { return }

        switch phase {
        case .idle, .starting:
            show(.idle, label: "", meta: "", rows: [], footer: "")
        case .watching:
            show(.watching, label: "Watching", detail: "Do the task as you usually do", meta: Self.clock(watch.elapsedSeconds),
                 dot: .pulse, rows: watchLog, footer: Self.watchFooter)
        case .stopped:
            show(.stopped, label: "Stopped", detail: "Review it in Understudy",
                 meta: Self.clock(watch.elapsedSeconds), rows: watchLog, footer: Self.watchFooter)
        }
    }

    // MARK: After teaching

    /// Under a skill whose steps came from a recording.
    static let learnedFooter = "Steps from your recording · replayed exactly, no AI"

    func showLearned(_ skill: Skill) {
        let token = beginOverlay()
        let notes = skill.rules.split(whereSeparator: \.isNewline).count
        let steps = skill.definition.steps
        guard steps.isEmpty else {
            let shown = steps.prefix(3).map { step in
                step.executor == .unsupported
                    ? row(step.parameters["app"] ?? "Step", step.intent, end: "needs you", endTone: .hold)
                    : row(step.parameters["app"] ?? "Step", step.intent, end: "✓", endTone: .ok)
            }
            show(.learned, label: "New skill", detail: skill.name, meta: "\(steps.count) steps",
                 rows: shown + [row("Notes", "\(notes) saved with the skill", tone: .said)], footer: Self.learnedFooter)
            later(token, 4.5) { $0.endOverlay() }
            return
        }
        show(.learned, label: "New skill", detail: skill.name, meta: "3 steps", rows: [
            row("Sheet", "→ read the week's figures", end: "✓", endTone: .ok),
            row("Report", "→ fill your template", end: "✓", endTone: .ok),
            row("Missing", "→ flag it, never guess", end: "✓", endTone: .ok),
            row("Notes", "\(notes) saved with the skill", tone: .said),
        ], footer: "Simulated · prepared in advance, not learned by AI")
        later(token, 4.5) { $0.endOverlay() }
    }

    // MARK: Rehearsal (simulated, read-only)

    /// `record` saves the finished receipt (see `SkillLibrary.record`).
    func rehearse(_ skill: Skill, scenario: SampleCase, record: @escaping (Receipt) -> Receipt, done: @escaping (Receipt) -> Void) {
        let token = beginOverlay()
        let missing = scenario == .missing
        show(.rehearsing, label: "Rehearsing", detail: "Read-only · \(skill.client)", meta: missing ? "missing spend" : "sample week",
             dot: .rehearse, rows: [], footer: "Simulated · fixed sample inputs, nothing live changes")
        let steps: [NotchRow] = missing ? [
            row("Figures", "ad spend · empty", tone: .plain, end: "blocked", endTone: .hold),
            row("Report", "saved as incomplete draft", end: "partly", endTone: .hold),
            row("Email", "not drafted: report incomplete", end: "held", endTone: .hold),
        ] : [
            row("Figures", "sample week read", end: "match", endTone: .ok),
            row("Report", "filled from the template", end: "match", endTone: .ok),
            row("Notes", "kept with the report", tone: .said, end: "✓", endTone: .ok),
        ]
        Task { [weak self] in
            for step in steps {
                await self?.sleep(Self.rowSeconds)
                guard let self, self.generation == token else { return }
                self.rows.append(step)
            }
            await self?.sleep(1.0)
            guard let self, self.generation == token else { return }
            let receipt = record(SampleEngine.rehearse(skill: skill, scenario: scenario))
            self.showReceipt(receipt)
            done(receipt)
        }
    }

    func showReceipt(_ receipt: Receipt) {
        let token = beginOverlay()
        show(.receipt, label: "Receipt", detail: receipt.missingSpend ? "Not ready to send" : "Ready for your review",
             meta: receipt.date.formatted(date: .omitted, time: .shortened), rows: receipt.missingSpend ? [
                row("Spend", "blocked · not verifiable", end: "needs you", endTone: .hold),
                row("Report", "incomplete draft", end: "partly", endTone: .hold),
                row("Tracker", "not connected", end: "—"),
                row("Email", "held back", end: "held", endTone: .hold),
             ] : [
                row("Figures", "sample only", end: "done", endTone: .ok),
                row("Report", "created locally", end: "ready", endTone: .ok),
                row("Tracker", "not connected", end: "—"),
                row("Email", "not sent", end: "—"),
             ], footer: "Simulated receipt · sample data")
        later(token, 15) { $0.endOverlay() }
    }

    // MARK: Menu

    /// Opens the menu out of the notch (clicked at rest). Anything that happens next (Watch, a
    /// countdown, a run) takes the notch over from it.
    /// The menu opens over a notch with nothing to show: at rest, or a stopped Watch tucked away.
    var canShowMenu: Bool { mode == .idle || mode == .stopped }

    func showMenu() {
        guard canShowMenu else { return }
        _ = beginOverlay()
        show(.menu, label: "Understudy", meta: "", rows: [], footer: "")
    }

    func hideMenu() {
        if mode == .menu { endOverlay() }
    }

    /// Clears a New skill or Receipt strip. Watch and rehearsal keep going.
    func dismiss() {
        // A run, a rehearsal, and the countdown before a triggered run aren't dismissed by a click:
        // the click opens the run, or (during the countdown) cancels it.
        guard overlayActive, mode != .rehearsing, mode != .running, mode != .scheduled else { return }
        endOverlay()
    }

    // MARK: Running a skill (real)

    static let runFooter = "Running on this Mac · click to open"
    static let runReceiptFooter = "Receipt saved · click to see it"

    /// The run in progress, kept so the strip returns to it after another message (e.g. New skill).
    private var run: (name: String, steps: [SkillDefinition.Step], results: [StepOutcome], current: Int?, pause: RunEngine.Pause?)?

    /// The run in progress: the steps done so far and the one running or waiting for the person.
    func showRun(_ name: String, steps: [SkillDefinition.Step], results: [StepOutcome], current: Int?, pause: RunEngine.Pause?) {
        run = (name, steps, results, current, pause)
        runPause = pause
        if mode != .running { _ = beginOverlay() }
        var rows: [NotchRow] = []
        for (index, step) in steps.enumerated() where results[index].status != .notRun || index == current {
            let app = step.parameters["app"] ?? "Step"
            switch results[index].status {
            case .done: rows.append(row(app, step.intent, end: "✓", endTone: .ok))
            case .skipped: rows.append(row(app, step.intent, end: "skipped"))
            case .blocked, .failed: rows.append(row(app, step.intent, end: "needs you", endTone: .hold))
            case .notRun: rows.append(row(app, step.intent, end: pause == nil ? "…" : "waiting", endTone: pause == nil ? .plain : .hold))
            }
        }
        let finished = results.filter { $0.status != .notRun }.count
        let label = pause == .approval ? "Needs your OK" : pause == .confirmation ? "Next step?" : "Running"
        show(.running, label: label, detail: pause != nil ? current.map { steps[$0].intent } : name,
             meta: "\(finished)/\(steps.count)", dot: pause == nil ? .pulse : .steady, rows: rows, footer: Self.runFooter)
    }

    /// The end of a run: its receipt, for a few seconds.
    func showRunReceipt(_ receipt: Receipt) {
        run = nil
        runPause = nil
        let token = beginOverlay()
        let rows = receipt.steps.enumerated().map { index, step in
            row("Step \(index + 1)", step.step, end: step.status == "Done" ? "✓" : step.status == "Skipped" || step.status == "Not run" ? "–" : "needs you",
                endTone: step.status == "Done" ? .ok : step.status == "Skipped" || step.status == "Not run" ? .plain : .hold)
        }
        show(.receipt, label: receipt.status == "Completed" ? "Done" : receipt.status, detail: receipt.skillName, meta: "",
             dot: .steady, rows: rows, footer: Self.runReceiptFooter)
        later(token, 15) { $0.endOverlay() }
    }

    static let countdownFooter = "Triggered run · click the notch to cancel"

    /// The countdown before a triggered run. Clicking the notch cancels it (see `Scheduler`).
    func showCountdown(_ name: String, seconds: Int) {
        if mode != .scheduled { _ = beginOverlay() }
        show(.scheduled, label: "Running in \(seconds)s", detail: name, meta: "", dot: .steady,
             rows: [row("Understudy", "will open apps and type for you", end: "\(seconds)")], footer: Self.countdownFooter)
    }

    func hideCountdown() {
        if mode == .scheduled { endOverlay() }
    }

    /// A triggered run that couldn't start, and why, for a few seconds.
    func showRunProblem(_ name: String, reason: String) {
        // A countdown stays in front: clicking it must still cancel that run.
        guard mode != .scheduled else { return }
        let token = beginOverlay()
        show(.receipt, label: "Didn't run", detail: name, meta: "", dot: .steady,
             rows: [row("Why", reason, end: "needs you", endTone: .hold)], footer: Self.runReceiptFooter)
        later(token, 8) { $0.endOverlay() }
    }

    // MARK: Landing-page demonstration (`--notch-demo`)

    func playDemo() {
        let token = beginOverlay()
        let frames = Self.demoFrames
        Task { [weak self] in
            while true {
                for frame in frames {
                    guard let self, self.generation == token else { return }
                    frame.apply(self)
                    await self.sleep(frame.seconds)
                }
            }
        }
    }

    private struct DemoFrame {
        let seconds: Double
        let apply: @MainActor (NotchActivity) -> Void
    }

    // The same frames and wording as the landing page's hero demo.
    private static let demoFrames: [DemoFrame] = {
        let concept = "Concept demonstration · not the working app"
        func watching(_ meta: String, _ add: [(String, String, NotchRow.Tone)]) -> DemoFrame {
            DemoFrame(seconds: 1.3) { a in
                a.show(.demo, label: "Watching", detail: nil, meta: meta, dot: .pulse,
                       rows: a.rows + add.map { a.row($0.0, $0.1, tone: $0.2) }, footer: concept)
            }
        }
        return [
            DemoFrame(seconds: 2.0) { a in a.show(.idle, label: "", meta: "", rows: [], footer: "") },
            DemoFrame(seconds: 1.3) { _ in },
            DemoFrame(seconds: 1.0) { a in a.show(.demo, label: "Watching", detail: nil, meta: "0:02", dot: .pulse, rows: [], footer: concept) },
            watching("0:09", [("Sheets", "opened “Norte – campaign data”", .plain)]),
            watching("0:21", [("Sheets", "copied week 38 totals", .plain)]),
            watching("0:40", [("Drive", "read this week's notes", .plain)]),
            watching("1:12", [("Sheets", "tracker row 14 → Ready", .ok)]),
            watching("1:30", [("Gmail", "drafted email to Leo", .plain)]),
            DemoFrame(seconds: 2.3) { a in
                a.show(.demo, label: "Watching", detail: nil, meta: "1:34", dot: .pulse,
                       rows: a.rows + [a.row("Your rule", "missing number → ask me", tone: .said)], footer: concept)
            },
            DemoFrame(seconds: 3.4) { a in
                a.show(.demo, label: "New skill", detail: "Weekly client update", meta: "6 steps", rows: [
                    a.row("Sheets", "→ connector", end: "✓", endTone: .ok),
                    a.row("Docs", "→ connector", end: "✓", endTone: .ok),
                    a.row("Gmail", "→ connector, draft only", end: "✓", endTone: .ok),
                    a.row("Summary", "→ AI step + memory", tone: .said),
                ], footer: concept)
            },
            DemoFrame(seconds: 1.3) { a in a.show(.demo, label: "Rehearsing", detail: "Read-only", meta: "3 past weeks", dot: .rehearse, rows: [], footer: concept) },
            DemoFrame(seconds: 1.4) { a in a.appendDemo(a.row("Week 36", "vs. what you sent", end: "match", endTone: .ok)) },
            DemoFrame(seconds: 1.4) { a in a.appendDemo(a.row("Week 37", "vs. what you sent", end: "match", endTone: .ok)) },
            DemoFrame(seconds: 3.2) { a in a.appendDemo(a.row("Week 38", "“click rate” vs “CTR”", end: "1 diff", endTone: .hold)) },
            DemoFrame(seconds: 1.3) { a in a.show(.demo, label: "Running", detail: "Week 39", meta: "Mon 9:12", rows: [], footer: concept) },
            DemoFrame(seconds: 1.5) { a in a.appendDemo(a.row("Sheets", "ad spend · C12 empty", end: "blocked", endTone: .hold)) },
            DemoFrame(seconds: 1.4) { a in a.appendDemo(a.row("Report", "saved as incomplete draft", end: "partly", endTone: .hold)) },
            DemoFrame(seconds: 1.3) { a in a.appendDemo(a.row("Tracker", "row 14 → Needs input", end: "done", endTone: .ok)) },
            DemoFrame(seconds: 1.3) { a in a.appendDemo(a.row("Email", "not drafted: report incomplete", end: "held", endTone: .hold)) },
            DemoFrame(seconds: 4.6) { a in
                a.show(.demo, label: "Receipt", detail: "Not ready to send", meta: "1m 40s", rows: [
                    a.row("Spend", "blocked · not verifiable", end: "needs you", endTone: .hold),
                    a.row("Report", "partly done", end: "verified", endTone: .ok),
                    a.row("Tracker", "needs input", end: "verified", endTone: .ok),
                    a.row("Email", "held back", end: "verified", endTone: .ok),
                ], footer: concept)
            },
        ]
    }()

    private func appendDemo(_ row: NotchRow) {
        rows = Array((rows + [row]).suffix(4))
    }

    // MARK: Helpers

    private func show(_ mode: Mode, label: String, detail: String? = nil, meta: String, dot: Dot = .steady, rows: [NotchRow], footer: String) {
        self.mode = mode
        self.label = label
        self.detail = detail
        self.meta = meta
        self.dot = dot
        self.rows = Array(rows.suffix(4))
        self.footer = footer
    }

    private func row(_ app: String, _ text: String, tone: NotchRow.Tone = .plain, end: String? = nil, endTone: NotchRow.Tone = .plain) -> NotchRow {
        nextID += 1
        return NotchRow(id: nextID, app: app, text: text, tone: tone, end: end, endTone: endTone)
    }

    private func ruleRow(_ text: String) -> NotchRow { row("Your rule", text, tone: .said) }

    private func beginOverlay() -> Int {
        generation += 1
        overlayActive = true
        return generation
    }

    private func cancelOverlay() {
        generation += 1
        overlayActive = false
    }

    private func endOverlay() {
        cancelOverlay()
        if let run { return showRun(run.name, steps: run.steps, results: run.results, current: run.current, pause: run.pause) }
        watchChanged()
    }

    private func later(_ token: Int, _ seconds: Double, _ work: @escaping @MainActor (NotchActivity) -> Void) {
        Task { [weak self] in
            await self?.sleep(seconds)
            guard let self, self.generation == token else { return }
            work(self)
        }
    }

    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}
