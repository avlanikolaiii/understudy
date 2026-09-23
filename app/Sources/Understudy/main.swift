import AppKit
import Carbon

/// ⌥ Space from anywhere. Uses a Carbon hot key, which doesn't need Accessibility access.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x5553_5459), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(model: model)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "theatermasks", accessibilityDescription: "Understudy")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Understudy", action: #selector(openPanel), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Understudy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            Task { @MainActor in self?.notch.toggle() }
        }
        model.start()
    }

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
