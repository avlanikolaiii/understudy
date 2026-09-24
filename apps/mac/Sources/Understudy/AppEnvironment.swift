import Foundation

/// The app's one set of objects, shared by the main window, the notch, the menus, and the
/// self-test. With --self-test they use a temporary library, no server, a test clock, and faster
/// notch timings (see SelfTest.swift). New parts of the app are created here, once.
@MainActor
final class AppEnvironment {
    let selfTest: SelfTestOptions?
    let model: AppModel
    let library: SkillLibrary
    let watch: WatchSession
    let activity: NotchActivity
    let ui = WorkspaceState()
    let shortcuts = ShortcutManager()

    init(arguments: [String]) {
        let selfTest = SelfTestOptions(arguments: arguments)
        self.selfTest = selfTest
        model = AppModel(config: selfTest == nil ? AppConfig.load() : nil)
        library = SkillLibrary(auth: model, file: selfTest?.libraryFile ?? .standard)
        watch = selfTest.map { options in WatchSession(now: { options.clock.now() }) } ?? WatchSession()
        activity = selfTest.map { [watch] in NotchActivity(watch: watch, sleep: $0.sleep) } ?? NotchActivity(watch: watch)
    }
}
