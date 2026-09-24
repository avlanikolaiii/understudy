import AppKit
import UnderstudyCore

/// Watch on a real Mac: the screen video (`ScreenRecorder`) and the action log (`ActionMonitor`).
/// Accessibility access is checked before anything starts; the screen is whatever the person
/// picks in macOS's picker.
@MainActor
final class ScreenCapture: CaptureSource {
    private let actions = ActionMonitor()
    private var screen: ScreenRecorder?

    static let accessibilityNeeded = "Understudy needs Accessibility access to note which apps, buttons, and fields you use. "
        + "Turn on Understudy in System Settings → Privacy & Security → Accessibility, then start Watch again."

    func start(folder: URL, clock: @escaping () -> Double, onAction: @escaping (RecordedAction) -> Void,
               ended: @escaping () -> Void, ready: @escaping (Error?) -> Void) {
        guard AX.isTrusted else {
            AX.askForTrust()
            return ready(CaptureError(message: Self.accessibilityNeeded))
        }
        // Sharing can end outside Understudy (the menu bar, or the recorded window closes): Watch stops too.
        let recorder = ScreenRecorder(url: folder.appendingPathComponent("screen.mov"), ended: ended)
        screen = recorder
        recorder.start { [weak self] error in
            guard let self, self.screen === recorder else { return }
            if let error {
                self.screen = nil
                return ready(error)
            }
            self.actions.start(clock: clock, emit: onAction)
            ready(nil)
        }
    }

    func stop(done: @escaping (VideoResult) -> Void) {
        actions.stop()
        guard let screen else { return done(.none) }
        self.screen = nil
        screen.stop(done: done)
    }
}
