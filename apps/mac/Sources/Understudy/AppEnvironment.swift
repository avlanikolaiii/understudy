import Foundation

/// The app's one set of objects, shared by the main window, the notch, the menus, and the
/// self-test. With --self-test they use a temporary library, no server, a test clock, and faster
/// notch timings (see SelfTest.swift). New parts of the app are created here, once.
@MainActor
final class AppEnvironment {
    let selfTest: SelfTestOptions?
    let model: AppModel
    let library: SkillLibrary
    /// Where Watch's actions and video come from: the screen, or the self-test's script.
    let capture: CaptureSource
    let watch: WatchSession
    let activity: NotchActivity
    let ui = WorkspaceState()
    let shortcuts = ShortcutManager()

    /// Recordings stay on this Mac, one folder each.
    static var recordings: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Understudy/recordings")
    }

    init(arguments: [String]) {
        let selfTest = SelfTestOptions(arguments: arguments)
        self.selfTest = selfTest
        model = AppModel(config: selfTest == nil ? AppConfig.load() : nil)
        library = SkillLibrary(auth: model, file: selfTest?.libraryFile ?? .standard)
        if let selfTest {
            capture = ScriptedCapture()
            watch = WatchSession(source: capture, folder: selfTest.recordings, now: { selfTest.clock.now() })
        } else {
            capture = ScreenCapture()
            watch = WatchSession(source: capture, folder: Self.recordings)
        }
        activity = selfTest.map { [watch] in NotchActivity(watch: watch, sleep: $0.sleep) } ?? NotchActivity(watch: watch)
    }
}
