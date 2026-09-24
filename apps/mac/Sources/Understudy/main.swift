import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var env = AppEnvironment(arguments: CommandLine.arguments)
    private(set) var notch: NotchController!
    private var statusItem: NSStatusItem!
    private var shortcutSettings: ShortcutSettingsController!
    private var shortcutObservation: AnyCancellable?
    private var workspace: WorkspaceController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutSettings = ShortcutSettingsController(manager: env.shortcuts)
        workspace = WorkspaceController(auth: env.model, library: env.library, ui: env.ui, watch: env.watch, activity: env.activity,
                                        openSettings: { [weak self] in self?.shortcutSettings.show() })
        notch = NotchController(activity: env.activity, onTap: { [weak self] page in self?.workspace.show(page) })
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
        case .idle, .demo:
            env.ui.startWatch(env.watch)
            // If Watch can't start (e.g. no Accessibility access), show why.
            if env.watch.problem != nil { workspace.show() }
        }
    }

    /// Email sign-in links and OAuth redirects arrive as understudy://auth-callback?...
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { env.model.handle(url: url) }
        workspace.show(.account)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
