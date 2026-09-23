import Combine
import Foundation

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
/// Rehearsing (read-only) → Receipt. Everything shown here is simulated and says so.
@MainActor
final class NotchActivity: ObservableObject {
    enum Mode: Equatable { case idle, watching, stopped, learned, rehearsing, receipt, demo }
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

    private let watch: WatchSession
    private var bag = Set<AnyCancellable>()
    private var watchLog: [NotchRow] = []
    private var loggedSteps = 0
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
        Publishers.CombineLatest3(watch.$phase, watch.$elapsedSeconds, watch.$rules)
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
        case .rehearsing, .receipt: .results
        case .idle, .demo: .home
        }
    }

    // MARK: Watch (simulated replay)

    func watchChanged() {
        let phase = watch.phase
        if phase == .playing && lastPhase != .playing {
            // A new or replayed Watch always takes over the notch.
            cancelOverlay()
            watchLog = watch.rules.map { ruleRow($0) }
            loggedSteps = 0
            loggedRules = watch.rules.count
        }
        while loggedSteps < watch.completedSteps {
            let step = WatchSession.steps[loggedSteps]
            watchLog.append(row(step.app, step.noted, end: "✓", endTone: .ok))
            loggedSteps += 1
        }
        while loggedRules < watch.rules.count {
            watchLog.append(ruleRow(watch.rules[loggedRules]))
            loggedRules += 1
        }
        lastPhase = phase
        guard !overlayActive else { return }

        switch phase {
        case .idle:
            show(.idle, label: "", meta: "", rows: [], footer: "")
        case .playing:
            show(.watching, label: "Watching", detail: "Weekly client update", meta: Self.clock(watch.elapsedSeconds),
                 dot: .pulse, rows: watchLog, footer: "Simulated replay · nothing is recorded")
        case .stopped, .finished:
            show(.stopped, label: phase == .finished ? "Replayed" : "Stopped", detail: "Review it in Understudy",
                 meta: Self.clock(watch.elapsedSeconds), rows: watchLog, footer: "Simulated replay · nothing is recorded")
        }
    }

    // MARK: After teaching

    func showLearned(_ skill: Skill) {
        let token = beginOverlay()
        let notes = skill.rules.split(whereSeparator: \.isNewline).count
        show(.learned, label: "New skill", detail: skill.name, meta: "\(WatchSession.steps.count) steps", rows: [
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

    /// Clears a New skill or Receipt strip. Watch and rehearsal keep going.
    func dismiss() {
        guard overlayActive, mode != .rehearsing else { return }
        endOverlay()
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
