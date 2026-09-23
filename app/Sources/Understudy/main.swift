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

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(model: model)
        shortcutSettings = ShortcutSettingsController(manager: shortcuts)
        model.openSettings = { [weak self] in self?.shortcutSettings.show() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "theatermasks", accessibilityDescription: "Understudy")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Understudy", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
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
    }

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
    app.setActivationPolicy(.accessory)
    app.run()
}
