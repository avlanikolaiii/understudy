import Foundation
import UnderstudyCore

@main
struct WatchChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-watch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var time: TimeInterval = 100
        let capture = ScriptedCapture()
        let session = WatchSession(source: capture, folder: folder, now: { time })
        precondition(session.phase == .idle && !session.isPresented)

        // A capture that can't start (e.g. no Accessibility access) leaves Watch idle, says why, and keeps no folder.
        capture.failure = "Needs Accessibility access."
        session.start(automaticTicks: false)
        precondition(session.phase == .idle && session.problem == "Needs Accessibility access.")
        precondition((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty ?? true)
        capture.failure = nil

        session.start(automaticTicks: false)
        precondition(session.isWatching && session.problem == nil && session.clockText == "00:00" && session.actions.isEmpty)
        session.ruleDraft = " \n "
        session.addRule()
        precondition(session.rules.isEmpty)
        session.ruleDraft = "  Never estimate missing spend.  "
        session.addRule()
        precondition(session.rules == ["Never estimate missing spend."] && session.ruleDraft.isEmpty)

        // Actions arrive in order, stamped on Watch's clock.
        time += 4.9
        session.advance()
        precondition(capture.emitNext())
        precondition(session.elapsedSeconds == 4 && session.actions.count == 1 && abs(session.actions[0].t - 4.9) < 0.001)
        time += 7
        session.advance()
        capture.emitNext(); capture.emitNext()
        precondition(session.actions.map(\.kind) == [.appSwitch, .appSwitch, .selection] && session.clockText == "00:11")

        // Stop saves the recording: actions, notes (including a pending one), and duration.
        session.ruleDraft = "Keep email as a draft."
        session.stop()
        precondition(session.phase == .stopped && session.rules.count == 2)
        precondition(!capture.emitNext())   // nothing records after Stop
        let saved = try JSONDecoder.iso.decode(Recording.self, from: Data(contentsOf: session.recordingFolder.appendingPathComponent("recording.json")))
        precondition(saved.actions.count == 3 && saved.notes == session.rules && abs(saved.duration - 11.9) < 0.001 && saved.video == nil)
        precondition(saved.id == session.recording?.id && saved.actions == session.recording?.actions)
        // A note added after Stop is saved too.
        session.ruleDraft = "Review before sharing."
        session.addRule()
        let updated = try JSONDecoder.iso.decode(Recording.self, from: Data(contentsOf: session.recordingFolder.appendingPathComponent("recording.json")))
        precondition(updated.notes.count == 3)
        time += 100
        session.advance()
        precondition(session.elapsedSeconds == 11)

        // Recording again keeps the notes, starts a new folder, and forgets the old take's actions.
        let firstFolder = session.recordingFolder
        session.start(keepingRules: true, automaticTicks: false)
        precondition(session.isWatching && session.actions.isEmpty && session.rules.count == 3 && session.recordingFolder != firstFolder)
        precondition(FileManager.default.fileExists(atPath: firstFolder.appendingPathComponent("recording.json").path))
        session.dismiss()
        precondition(!session.isPresented)
        session.start(automaticTicks: false)
        precondition(session.rules.isEmpty && session.ruleDraft.isEmpty && session.elapsedSeconds == 0)
        session.dismiss()
        time += 10
        session.advance()
        precondition(session.phase == .idle && session.elapsedSeconds == 0)

        // Typing still pending when Stop is pressed is kept, and saved.
        session.start(automaticTicks: false)
        capture.pendingTyping = "last words"
        session.stop()
        precondition(session.actions.last?.text == "last words" && session.recording?.actions.last?.text == "last words")
        precondition(WatchSession.load(session.recordingFolder)?.actions.last?.text == "last words")

        // Stopping sharing from macOS's menu bar stops Watch and saves the take.
        session.start(automaticTicks: false)
        capture.emitNext()
        capture.endSharing()
        precondition(session.phase == .stopped && session.recording?.actions.count == 1)
        precondition(!capture.emitNext())

        // The video finishes after Stop: it lands on its own take, even after Record again.
        capture.video = "screen.mov"
        session.start(automaticTicks: false)
        session.stop()
        capture.finishVideos()
        precondition(session.recording?.video == "screen.mov" && WatchSession.load(session.recordingFolder)?.video == "screen.mov")
        session.start(automaticTicks: false)
        let earlier = session.recordingFolder
        session.stop()
        session.start(keepingRules: true, automaticTicks: false)
        capture.finishVideos()
        precondition(WatchSession.load(earlier)?.video == "screen.mov")
        precondition(session.isWatching && session.recording == nil)
        session.dismiss()
        capture.finishVideos()
        capture.video = nil

        // Password fields: nothing typed and no value is kept, even if a source reports them.
        let secret = RecordedAction(t: 1, kind: .typing, app: "Safari", element: .init(role: "AXTextField", subrole: "AXSecureTextField"),
                                    text: "hunter2", value: "hunter2")
        precondition(secret.text == nil && secret.value == nil && secret.summary == "typed a password (not recorded)")

        // The real Combine timer and its cancellation, not just manual ticks.
        let live = WatchSession(source: ScriptedCapture(), folder: folder)
        live.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        precondition(live.elapsedSeconds >= 1)
        live.stop()
        let stopped = live.elapsedSeconds
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        precondition(live.elapsedSeconds == stopped && live.phase == .stopped)
        print("PASS: start failure, ordered actions on Watch's clock, Stop saves the recording and notes, pending typing kept, sharing ended, late video on its own take, record again, reset, password redaction, and the timer")
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
