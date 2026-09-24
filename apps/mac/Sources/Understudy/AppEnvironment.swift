import Foundation
import UnderstudyCore

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
    /// Runs skills: on the real Mac through `AppPerformer`, in the self-test through `ScriptedPerformer`.
    let runner: RunController
    /// What performs each step: `AppPerformer` on a Mac, `ScriptedPerformer` in the self-test.
    let performer: StepPerformer
    /// Starts skills when their trigger fires.
    let scheduler: Scheduler
    /// A keyboard shortcut per skill.
    let skillShortcuts: SkillShortcuts
    /// Run notifications; none in the self-test.
    let notifier = Notifier()
    let ui = WorkspaceState()
    let shortcuts = ShortcutManager()

    /// Recordings stay on this Mac, one folder each.
    static var recordings: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Understudy/recordings")
    }

    static func runBlocker(watch: WatchSession, activity: NotchActivity, trusted: Bool) -> String? {
        if watch.isWatching || watch.phase == .starting { return "Watch is recording. Stop it before running a skill." }
        if activity.isRehearsing { return "A sample rehearsal is playing. Try again when it finishes." }
        return trusted ? nil : AppPerformer.accessibilityNeeded
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
        if selfTest != nil {
            performer = ScriptedPerformer()
            // Steps advance on the next pass of the run loop, so the self-test sees runs in progress.
            runner = RunController(library: library, activity: activity, performer: performer,
                                   ready: { [watch, activity] in Self.runBlocker(watch: watch, activity: activity, trusted: true) },
                                   wait: { _, then in DispatchQueue.main.async(execute: then) })
        } else {
            performer = AppPerformer()
            runner = RunController(library: library, activity: activity, performer: performer,
                                   ready: { [watch, activity] in Self.runBlocker(watch: watch, activity: activity, trusted: AX.isTrusted) })
        }
        // A run and Watch never overlap: the run's keystrokes would end up in the recording.
        watch.blocker = { [runner] in runner.isRunning ? "A skill is running. Stop it before starting Watch." : nil }
        runner.onReceipt = { [ui] id in ui.selectedReceipt = id }
        if let selfTest {
            // The self-test's own settings, clock, and timings; the person is never "using the Mac".
            scheduler = Scheduler(library: library, runner: runner, activity: activity, busy: { [watch, activity] in watch.isWatching || watch.phase == .starting || activity.isRehearsing },
                                  defaults: UserDefaults(suiteName: "understudy-self-test-\(UUID().uuidString)")!,
                                  now: { Date(timeIntervalSince1970: selfTest.clock.now()) }, sleep: selfTest.sleep,
                                  idleSeconds: { 3600 })
        } else {
            scheduler = Scheduler(library: library, runner: runner, activity: activity,
                                  busy: { [watch, activity] in watch.isWatching || watch.phase == .starting || activity.isRehearsing })
        }
        if selfTest != nil {
            // Shortcuts are checked without registering real system hot keys.
            skillShortcuts = SkillShortcuts(defaults: UserDefaults(suiteName: "understudy-self-test-keys-\(UUID().uuidString)")!,
                                            reserved: { [shortcuts] in shortcuts.shortcut }, install: { _, _ in NSObject() })
        } else {
            skillShortcuts = SkillShortcuts(reserved: { [shortcuts] in shortcuts.shortcut })
            runner.notify = { [notifier] title, body, page in notifier.post(title: title, body: body, opens: page) }
        }
    }
}
