import Combine
import Foundation
import UnderstudyCore

/// Where Watch's actions and video come from. On a Mac it is `ScreenCapture` (the screen and
/// Accessibility); the self-test and the checks use `ScriptedCapture`.
@MainActor
protocol CaptureSource: AnyObject {
    /// Starts capturing into `folder`. Calls `ready(nil)` once capture runs, or `ready(error)`.
    /// Actions arrive in order, on the main actor; `clock` gives seconds since Watch started.
    func start(folder: URL, clock: @escaping () -> Double, onAction: @escaping (RecordedAction) -> Void,
               ready: @escaping (Error?) -> Void)
    /// Stops capturing. `done` gets the video's file name in `folder`, if the screen was recorded.
    func stop(done: @escaping (String?) -> Void)
}

/// Watch: records one demonstration. It starts only when the person asks, shows what it records,
/// and stops on Stop or the shortcut. Each recording is a folder on this Mac with the video and
/// `recording.json` (the actions and notes), which learning reads.
@MainActor
final class WatchSession: ObservableObject {
    enum Phase { case idle, starting, watching, stopped }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var actions: [RecordedAction] = []
    @Published private(set) var rules: [String] = []
    @Published var ruleDraft = ""
    /// Why Watch couldn't start or save, in words the person can act on.
    @Published private(set) var problem: String?
    /// The finished recording, once Watch has stopped.
    @Published private(set) var recording: Recording?

    private let source: CaptureSource
    private let folder: URL
    private let now: () -> TimeInterval
    private var timer: AnyCancellable?
    private var startedAt: TimeInterval = 0
    private var startedDate = Date()
    private var id = UUID()

    init(source: CaptureSource, folder: URL, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.source = source
        self.folder = folder
        self.now = now
    }

    var isWatching: Bool { phase == .watching }
    var isPresented: Bool { phase == .watching || phase == .stopped }
    var clockText: String { String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60) }
    var canAddRule: Bool { !ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// This recording's folder.
    var recordingFolder: URL { folder.appendingPathComponent(id.uuidString) }

    /// Starts a new recording. `keepingRules` keeps the notes from the previous take.
    func start(keepingRules: Bool = false, automaticTicks: Bool = true) {
        guard phase == .idle || phase == .stopped else { return }
        if keepingRules { addRule() } else { rules = []; ruleDraft = "" }
        id = UUID(); recording = nil; problem = nil
        actions = []; elapsedSeconds = 0
        phase = .starting
        do {
            try FileManager.default.createDirectory(at: recordingFolder, withIntermediateDirectories: true)
        } catch {
            return fail("Understudy couldn't create a folder for the recording: \(error.localizedDescription)")
        }
        let take = id
        source.start(folder: recordingFolder, clock: { [weak self] in self.map { $0.now() - $0.startedAt } ?? 0 },
                     onAction: { [weak self] action in self?.record(action, take: take) },
                     ready: { [weak self] error in self?.began(error, take: take, automaticTicks: automaticTicks) })
    }

    func advance() {
        guard isWatching else { return }
        let elapsed = max(0, Int(now() - startedAt))
        if elapsed != elapsedSeconds { elapsedSeconds = elapsed }
    }

    func stop() {
        guard isWatching else { return }
        advance()
        addRule()
        phase = .stopped
        timer?.cancel(); timer = nil
        let take = id, duration = now() - startedAt
        save(duration: duration, video: nil)
        source.stop { [weak self] video in
            guard let self, self.id == take, video != nil else { return }
            self.save(duration: duration, video: video)
        }
    }

    func addRule() {
        guard isPresented else { return }
        let text = ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        rules.append(text)
        ruleDraft = ""
        if let recording { save(duration: recording.duration, video: recording.video) }
    }

    /// Ends the session. A finished recording stays in its folder for learning.
    func dismiss() {
        if phase == .starting {
            source.stop { _ in }
            try? FileManager.default.removeItem(at: recordingFolder)
        }
        stop()
        timer?.cancel(); timer = nil
        phase = .idle
    }

    // MARK: Private

    private func began(_ error: Error?, take: UUID, automaticTicks: Bool) {
        guard phase == .starting, id == take else { return }
        if let error {
            try? FileManager.default.removeItem(at: recordingFolder)
            return fail(error.localizedDescription)
        }
        startedAt = now()
        startedDate = Date()
        phase = .watching
        if automaticTicks {
            timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.advance() }
        }
    }

    private func record(_ action: RecordedAction, take: UUID) {
        guard isWatching, id == take else { return }
        var action = action
        action.redactSecureFields()
        actions.append(action)
    }

    private func fail(_ message: String) {
        problem = message
        phase = .idle
    }

    private func save(duration: Double, video: String?) {
        let finished = Recording(id: id, startedAt: startedDate, duration: duration, actions: actions, notes: rules, video: video)
        recording = finished
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(finished).write(to: recordingFolder.appendingPathComponent("recording.json"), options: .atomic)
        } catch {
            problem = "The recording couldn't be saved: \(error.localizedDescription)"
        }
    }
}

/// A fixed demonstration for the self-test and the checks: the teaching script's actions, one per
/// `emitNext()`. It records nothing from the screen.
@MainActor
final class ScriptedCapture: CaptureSource {
    static let script: [RecordedAction] = [
        RecordedAction(t: 0, kind: .appSwitch, app: "Numbers", bundle: "com.apple.iWork.Numbers", window: "campaign_data"),
        RecordedAction(t: 0, kind: .appSwitch, app: "TextEdit", bundle: "com.apple.TextEdit", window: "weekly-update.md"),
        RecordedAction(t: 0, kind: .selection, app: "Numbers", bundle: "com.apple.iWork.Numbers", window: "campaign_data",
                       cells: "D5=1200 E5=48 F5=320.50 G5=6"),
        RecordedAction(t: 0, kind: .typing, app: "TextEdit", bundle: "com.apple.TextEdit", window: "weekly-update.md",
                       element: .init(role: "AXTextArea"), text: "| Impressions | 1,200 |"),
        RecordedAction(t: 0, kind: .click, app: "TextEdit", bundle: "com.apple.TextEdit", window: "weekly-update.md",
                       element: .init(role: "AXButton", title: "Save")),
    ]

    /// When set, `start` fails with this message, as a missing permission would.
    var failure: String?
    private var clock: () -> Double = { 0 }
    private var onAction: ((RecordedAction) -> Void)?
    private var next = 0

    func start(folder: URL, clock: @escaping () -> Double, onAction: @escaping (RecordedAction) -> Void,
               ready: @escaping (Error?) -> Void) {
        if let failure { return ready(CaptureError(message: failure)) }
        self.clock = clock; self.onAction = onAction; next = 0
        ready(nil)
    }

    func stop(done: @escaping (String?) -> Void) {
        onAction = nil
        done(nil)
    }

    /// Emits the script's next action. Returns false when the script is done or nothing is recording.
    @discardableResult
    func emitNext() -> Bool {
        guard let onAction, next < Self.script.count else { return false }
        var action = Self.script[next]
        action.t = clock()
        next += 1
        onAction(action)
        return true
    }
}

struct CaptureError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
