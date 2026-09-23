import Combine
import Foundation

/// A local, predefined replay of the Phase A teaching script. No capture or connectors.
@MainActor
final class WatchSession: ObservableObject {
    enum Phase { case idle, playing, stopped, finished }
    struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
        /// Short app name and past-tense note, for the notch strip.
        let app: String
        let noted: String
    }

    static let secondsPerStep = 5
    static let steps = [
        Step(id: 0, title: "Open the campaign sheet", detail: "Numbers · teaching sample · week 1", app: "Numbers", noted: "opened the campaign sheet"),
        Step(id: 1, title: "Open the weekly report template", detail: "TextEdit · local report copy", app: "TextEdit", noted: "opened the report template"),
        Step(id: 2, title: "Select the week's campaign figures", detail: "Impressions, clicks, spend, and leads", app: "Numbers", noted: "copied week 1 figures"),
        Step(id: 3, title: "Fill the report's numbers table", detail: "Week 1 totals from the teaching example", app: "TextEdit", noted: "filled the numbers table"),
        Step(id: 4, title: "Write the weekly summary", detail: "One sentence in the sample report", app: "TextEdit", noted: "wrote the summary")
    ]

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var rules: [String] = []
    @Published var ruleDraft = ""
    private var timer: AnyCancellable?
    private var startedAt: TimeInterval = 0
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var isPlaying: Bool { phase == .playing }
    var isPresented: Bool { phase != .idle }
    var duration: Int { Self.steps.count * Self.secondsPerStep }
    var completedSteps: Int { min(elapsedSeconds / Self.secondsPerStep, Self.steps.count) }
    var clockText: String { String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
    var canAddRule: Bool { !ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func start(keepingRules: Bool = false, automaticTicks: Bool = true) {
        timer?.cancel()
        if keepingRules { addRule() } else { rules = []; ruleDraft = "" }
        elapsedSeconds = 0
        startedAt = now()
        phase = .playing
        if automaticTicks {
            timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.advance() }
        }
    }

    func advance() {
        guard isPlaying else { return }
        let elapsed = min(duration, max(0, Int(now() - startedAt)))
        if elapsed != elapsedSeconds { elapsedSeconds = elapsed }
        if elapsed == duration {
            addRule()
            phase = .finished
            timer?.cancel()
            timer = nil
        }
    }

    func stop() {
        guard isPlaying else { return }
        advance()
        addRule()
        if isPlaying { phase = .stopped }
        timer?.cancel()
        timer = nil
    }

    func addRule() {
        guard isPresented else { return }
        let text = ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        rules.append(text)
        ruleDraft = ""
    }

    func dismiss() {
        stop()
        phase = .idle
    }
}
