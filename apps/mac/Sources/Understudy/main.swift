import AppKit
import Combine
import UnderstudyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var env = AppEnvironment(arguments: CommandLine.arguments)
    private(set) var notch: NotchController!
    private var statusItem: NSStatusItem!
    private var shortcutSettings: ShortcutSettingsController!
    private var shortcutObservation: AnyCancellable?
    private var skillsObservation: AnyCancellable?
    private var workspace: WorkspaceController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutSettings = ShortcutSettingsController(manager: env.shortcuts)
        workspace = WorkspaceController(auth: env.model, library: env.library, ui: env.ui, watch: env.watch, activity: env.activity,
                                        runner: env.runner, scheduler: env.scheduler, skillShortcuts: env.skillShortcuts, openSettings: { [weak self] in self?.shortcutSettings.show() })
        notch = NotchController(activity: env.activity, onTap: { [weak self] page in
            guard let self else { return }
            // During the countdown before a triggered run, a click cancels that run.
            if self.env.activity.mode == .scheduled { return self.env.scheduler.cancelPending() }
            // At rest, a click offers the skills to run (the self-test can't click a menu).
            if self.env.activity.mode == .idle, self.env.selfTest == nil, self.showSkillMenu() { return }
            self.workspace.show(page)
        })
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "theatermasks", accessibilityDescription: "Understudy")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Understudy", action: #selector(openWorkspace), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let watchItem = NSMenuItem(title: "Watch a Task", action: #selector(shortcutPressed), keyEquivalent: "")
        watchItem.target = self
        menu.addItem(watchItem)
        let settingsItem = NSMenuItem(title: "Keyboard Shortcut…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Understudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        shortcutObservation = env.shortcuts.objectWillChange.sink { [weak self, weak watchItem] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let label = self.env.shortcuts.shortcut.display
                self.env.model.shortcutLabel = self.env.shortcuts.isActive ? label : "Shortcut unavailable"
                watchItem?.title = self.env.shortcuts.isActive ? "Watch a Task · \(label)" : "Watch a Task"
            }
        }
        if let options = env.selfTest {
            // No global shortcut and no server: the test drives the same objects directly.
            Task { @MainActor in exit(await SelfTest(app: self, options: options).run()) }
            return
        }
        env.shortcuts.start { [weak self] in self?.shortcutPressed() }
        env.model.start()
        env.scheduler.start()
        env.notifier.open = { [weak self] page in self?.workspace.show(page == "skills" ? .skills : .results) }
        skillsObservation = env.library.$skills.receive(on: RunLoop.main).sink { [weak self] skills in
            self?.env.skillShortcuts.start(skills: skills.map(\.id)) { id in self?.runNow(id) }
        }
        if CommandLine.arguments.contains("--notch-demo") {
            // Plays the landing page's hero sequence in the real notch, for side-by-side comparison.
            env.activity.playDemo()
        } else {
            workspace.show()
        }
    }

    private func installMainMenu() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title)
            item.submenu = child; menu.addItem(item)
            return child
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target; menu.addItem(item)
        }
        let appMenu = submenu("Understudy")
        add(appMenu, "Settings…", #selector(openSettings), ",", target: self)
        appMenu.addItem(.separator())
        add(appMenu, "Hide Understudy", #selector(NSApplication.hide(_:)), "h")
        appMenu.addItem(.separator())
        add(appMenu, "Quit Understudy", #selector(NSApplication.terminate(_:)), "q")
        let file = submenu("File")
        add(file, "Teach a Skill", #selector(teachSkill), "n", target: self)
        add(file, "Open Workspace", #selector(openWorkspace), "1", target: self)
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        let windows = submenu("Window")
        add(windows, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(windows, "Zoom", #selector(NSWindow.performZoom(_:)), "")
        NSApplication.shared.windowsMenu = windows
        NSApplication.shared.mainMenu = menu
    }

    /// Quitting while Watch records, or while a stopped take's video is still being written,
    /// waits (up to 5 s) for the take to be saved.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard env.watch.isWatching || env.watch.savingVideos > 0 else { return .terminateNow }
        var replied = false
        let reply = { if !replied { replied = true; sender.reply(toApplicationShouldTerminate: true) } }
        if env.watch.isWatching { env.watch.stop() }
        env.watch.whenSaved(reply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: reply)
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Keep a focused settings recorder in place when the app is already visible.
        if !flag { workspace.show() }
        return true
    }

    @objc func teachSkill() { workspace.teachSkill() }

    @objc func openWorkspace() { workspace.show() }

    @objc func openSettings() { shortcutSettings.show() }

    /// The landing page's story: the shortcut starts Watch, and pressing it again stops Watch
    /// and opens the review in the main window.
    @objc func shortcutPressed() {
        // Stopping Watch always wins, even while a rehearsal or receipt is showing in the notch.
        if env.watch.isWatching {
            env.ui.reviewWatch(env.watch)
            workspace.show()
            return
        }
        switch env.activity.mode {
        case .watching:
            env.ui.reviewWatch(env.watch)
            workspace.show()
        case .stopped:
            workspace.show(.teach)
        case .learned, .receipt:
            env.activity.dismiss()
        case .rehearsing:
            workspace.show(.results)
        case .running:
            workspace.show(.skills)
        case .scheduled:
            env.scheduler.cancelPending()
        case .idle, .demo:
            env.ui.startWatch(env.watch)
            // If Watch can't start (e.g. no Accessibility access), show why.
            if env.watch.problem != nil { workspace.show() }
        }
    }

    /// Email sign-in links and OAuth redirects arrive as understudy://auth-callback?...;
    /// understudy://run?skill=<name or id>[&value=…] runs a skill (from Shortcuts, Raycast, Terminal).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.host == "run" { runFromLink(url); continue }
            env.model.handle(url: url)
            workspace.show(.account)
        }
    }

    // MARK: Starting skills from anywhere

    /// A skill's own shortcut: the person asked for it directly, so it runs at once.
    func runNow(_ id: UUID) {
        guard let skill = env.library.skills.first(where: { $0.id == id }) else { return }
        if !env.runner.start(skill, mode: .run) { reportProblem(skill.name, env.runner.problem ?? "It couldn't start.") }
    }

    /// Why a skill didn't start. A countdown in the notch stays there (a click on it must still
    /// cancel), so then it's said in a notification instead.
    private func reportProblem(_ name: String, _ reason: String) {
        if env.activity.mode == .scheduled {
            if env.selfTest == nil { env.notifier.post(title: "\(name) didn't run", body: reason, opens: "skills") }
        } else {
            env.activity.showRunProblem(name, reason: reason)
        }
    }

    /// The skill a link names: its id, or its name when exactly one skill with steps has it.
    static func skill(named wanted: String, in skills: [Skill]) -> Result<Skill, AppCommand.Problem> {
        if let skill = skills.first(where: { $0.id.uuidString.caseInsensitiveCompare(wanted) == .orderedSame }) {
            return skill.definition.steps.isEmpty ? .failure(.init(message: "That skill has no steps yet.")) : .success(skill)
        }
        let named = skills.filter { !$0.definition.steps.isEmpty && $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
        if named.count > 1 { return .failure(.init(message: "\(named.count) skills are called that. Use the skill's id in the link.")) }
        return named.first.map { .success($0) } ?? .failure(.init(message: "No skill with steps is called that."))
    }

    /// A link came from another app, so the run counts down first (and can be cancelled).
    func runFromLink(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let wanted = (items.first { $0.name == "skill" }?.value ?? "").trimmingCharacters(in: .whitespaces)
        let skill: Skill
        switch Self.skill(named: wanted, in: env.library.skills) {
        case .success(let found): skill = found
        case .failure(let problem): return reportProblem(wanted.isEmpty ? "Link" : wanted, problem.message)
        }
        var values: [String: String] = [:]
        for item in items where item.name != "skill" { values[item.name] = item.value ?? "" }
        env.scheduler.fire(skill, values: values, triggered: false)
    }

    /// Chosen from the notch's menu: counts down like a trigger, so a stray click can be undone.
    func runFromMenu(_ skill: Skill) { env.scheduler.fire(skill, triggered: false) }

    /// The skills that can run, under the notch. Returns false when there are none.
    private func showSkillMenu() -> Bool {
        let runnable = env.library.skills.filter { !$0.definition.steps.isEmpty }
        guard !runnable.isEmpty else { return false }
        let menu = NSMenu()
        for skill in runnable {
            let shortcut = env.skillShortcuts.shortcuts[skill.id].map { "   \($0.display)" } ?? ""
            let item = NSMenuItem(title: "Run \(skill.name)\(shortcut)", action: #selector(runFromMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = skill.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Understudy", action: #selector(openWorkspace), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        return true
    }

    @objc private func runFromMenuItem(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID, let skill = env.library.skills.first(where: { $0.id == id }) else { return }
        runFromMenu(skill)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
