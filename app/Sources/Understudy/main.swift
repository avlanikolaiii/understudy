import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchController!
    private var statusItem: NSStatusItem!
    private let shortcuts = ShortcutManager()
    private var shortcutSettings: ShortcutSettingsController!
    private var shortcutObservation: AnyCancellable?
    private var workspace: WorkspaceController!
    private let watch = WatchSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutSettings = ShortcutSettingsController(manager: shortcuts)
        workspace = WorkspaceController(watch: watch, openSettings: { [weak self] in self?.shortcutSettings.show() })
        model.openWorkspace = { [weak self] in self?.workspace.show() }
        notch = NotchController(model: model, watch: watch)
        model.openSettings = { [weak self] in self?.shortcutSettings.show() }
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "theatermasks", accessibilityDescription: "Understudy")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Understudy", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let workspaceItem = NSMenuItem(title: "Open workspace", action: #selector(openWorkspace), keyEquivalent: "o")
        workspaceItem.target = self
        menu.addItem(workspaceItem)
        let settingsItem = NSMenuItem(title: "Keyboard Shortcut…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Understudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        shortcutObservation = shortcuts.objectWillChange.sink { [weak self, weak open] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let label = self.shortcuts.shortcut.display
                self.model.shortcutLabel = self.shortcuts.isActive ? label : "Shortcut unavailable"
                open?.title = self.shortcuts.isActive ? "Open Understudy (\(label))" : "Open Understudy (shortcut unavailable)"
            }
        }
        shortcuts.start { [weak self] in self?.notch.toggle() }
        model.start()
        workspace.show()
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

    @objc private func teachSkill() { workspace.teachSkill() }

    @objc private func openWorkspace() { workspace.show() }

    @objc private func openSettings() { shortcutSettings.show() }

    @objc private func openPanel() { notch.expand() }

    /// Email sign-in links and OAuth redirects arrive as understudy://auth-callback?...
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model.handle(url: url) }
        notch.expand()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
