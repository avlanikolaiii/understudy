import Combine
import Foundation
import UnderstudyCore

/// Where Watch's actions and video come from. On a Mac it is `ScreenCapture` (the screen and
/// Accessibility); the self-test and the checks use `ScriptedCapture`.
@MainActor
protocol CaptureSource: AnyObject {
    /// Starts capturing into `folder`. Calls `ready(nil)` once capture runs, or `ready(error)`.
    /// Actions arrive in order, on the main actor; `clock` gives seconds since Watch started.
    /// `ended` runs if capture ends on its own, e.g. the person stops sharing from the menu bar.
    func start(folder: URL, clock: @escaping () -> Double, onAction: @escaping (RecordedAction) -> Void,
               ended: @escaping () -> Void, ready: @escaping (Error?) -> Void)
    /// Stops capturing. Actions still pending (e.g. typing not yet recorded) arrive before this
    /// returns. `done` says whether a video was saved in `folder`; a video finishes writing after
    /// Stop, so `done` comes later, possibly after another take has started.
    func stop(done: @escaping (VideoResult) -> Void)
}

/// How a take's screen video ended.
enum VideoResult: Equatable {
    case none
    case saved(String)
    case failed(String)
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
                     ended: { [weak self] in if self?.id == take { self?.stop() } },
                     ready: { [weak self] error in self?.began(error, take: take, automaticTicks: automaticTicks) })
    }

    func advance() {
        guard isWatching else { return }
        let elapsed = max(0, Int(now() - startedAt))
        if elapsed != elapsedSeconds { elapsedSeconds = elapsed }
    }

    /// Stops recording. `finished` runs once the video is written (or there is none), e.g. so the
    /// app can quit without losing the take.
    func stop(finished: @escaping () -> Void = {}) {
        guard isWatching else { return finished() }
        advance()
        addRule()
        timer?.cancel(); timer = nil
        let take = id, folder = recordingFolder, duration = now() - startedAt
        // Still watching while the source stops, so its last actions (pending typing) are kept.
        source.stop { [weak self] result in
            defer { finished() }
            let video: String
            switch result {
            case .none: return
            case .failed(let reason):
                if let self, self.id == take { self.problem = "The screen video couldn't be saved: \(reason) The steps were saved." }
                return
            case .saved(let name): video = name
            }
            // The video finishes after Stop. If another take has started since, update this take's file.
            if let self, self.id == take, let recording = self.recording {
                self.save(Recording(id: take, startedAt: recording.startedAt, duration: duration,
                                    actions: recording.actions, notes: recording.notes, video: video))
            } else if var saved = Self.load(folder) {
                saved.video = video
                try? Self.write(saved, to: folder)
            }
        }
        phase = .stopped
        if recording?.id != take {
            save(Recording(id: take, startedAt: startedDate, duration: duration, actions: actions, notes: rules, video: nil))
        }
    }

    func addRule() {
        guard isPresented else { return }
        let text = ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        rules.append(text)
        ruleDraft = ""
        if var recording { recording.notes = rules; save(recording) }
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

    private func save(_ finished: Recording) {
        recording = finished
        do {
            try Self.write(finished, to: recordingFolder)
        } catch {
            problem = "The recording couldn't be saved: \(error.localizedDescription)"
        }
    }

    static func write(_ recording: Recording, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(recording).write(to: folder.appendingPathComponent("recording.json"), options: .atomic)
    }

    static func load(_ folder: URL) -> Recording? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Recording.self, from: Data(contentsOf: folder.appendingPathComponent("recording.json")))
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
    /// When set, `stop` reports a video with this name a moment later, as the recorder does.
    /// `failingVideo` reports a failure instead.
    var video: String?
    static let failingVideo = "fail"
    /// Text "typed" but not yet recorded; `stop` records it first, as `ActionMonitor` does.
    var pendingTyping: String?
    private var clock: () -> Double = { 0 }
    private var onAction: ((RecordedAction) -> Void)?
    private var ended: (() -> Void)?
    private var next = 0
    private var finishing: [() -> Void] = []

    func start(folder: URL, clock: @escaping () -> Double, onAction: @escaping (RecordedAction) -> Void,
               ended: @escaping () -> Void, ready: @escaping (Error?) -> Void) {
        if let failure { return ready(CaptureError(message: failure)) }
        self.clock = clock; self.onAction = onAction; self.ended = ended; next = 0
        ready(nil)
    }

    func stop(done: @escaping (VideoResult) -> Void) {
        if let text = pendingTyping {
            onAction?(RecordedAction(t: clock(), kind: .typing, app: "TextEdit", element: .init(role: "AXTextArea"), text: text))
            pendingTyping = nil
        }
        onAction = nil; ended = nil
        guard let name = video else { return done(.none) }
        finishing.append { done(name == Self.failingVideo ? .failed("The disk is full.") : .saved(name)) }
    }

    /// Finishes the videos of stopped takes, as the recorder does a moment after Stop.
    func finishVideos() {
        let pending = finishing
        finishing = []
        pending.forEach { $0() }
    }

    /// The person stops sharing the screen from macOS's menu bar.
    func endSharing() {
        ended?()
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
