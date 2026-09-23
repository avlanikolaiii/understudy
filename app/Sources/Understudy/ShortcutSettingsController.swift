import AppKit
import Combine

/// An app-local key recorder. No global keyboard monitoring or new permissions.
@MainActor
final class ShortcutSettingsController: NSObject, NSWindowDelegate {
    private let manager: ShortcutManager
    private let window: NSWindow
    private let value = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let record = NSButton(title: "Record shortcut", target: nil, action: nil)
    private let reset = NSButton(title: "Restore default", target: nil, action: nil)
    private var monitor: Any?
    private var observation: AnyCancellable?

    init(manager: ShortcutManager) {
        self.manager = manager
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 290),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Understudy Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let heading = NSTextField(labelWithString: "Keyboard shortcut")
        heading.font = .systemFont(ofSize: 19, weight: .semibold)
        let explanation = NSTextField(wrappingLabelWithString: "Open or close the notch panel. During Watch, this shortcut stops the replay and shows the result.")
        explanation.textColor = .secondaryLabelColor
        value.font = .monospacedSystemFont(ofSize: 24, weight: .medium)
        value.setAccessibilityLabel("Current shortcut")
        record.bezelStyle = .rounded
        record.target = self; record.action = #selector(recordPressed)
        reset.bezelStyle = .rounded
        reset.target = self; reset.action = #selector(resetPressed)
        let buttons = NSStackView(views: [record, reset])
        buttons.orientation = .horizontal; buttons.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.setAccessibilityLabel("Shortcut status")
        let stack = NSStackView(views: [heading, explanation, value, buttons, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
                status.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }
        observation = manager.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.manager.isRecording, self.window.isKeyWindow else { return event }
            if event.keyCode == 53 { self.manager.cancelRecording(); return nil }
            if event.isARepeat { return nil }
            if let shortcut = KeyboardShortcut(event: event) { self.manager.change(to: shortcut) }
            else { self.manager.rejectKey() }
            return nil
        }
        window.center()
        refresh()
    }

    func show() {
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func recordPressed() {
        if manager.isRecording { manager.cancelRecording() } else { manager.beginRecording() }
    }

    @objc private func resetPressed() {
        manager.cancelRecording()
        manager.change(to: .defaultShortcut)
    }

    private func refresh() {
        value.stringValue = manager.shortcut.display
        record.title = manager.isRecording ? "Cancel recording" : "Record shortcut"
        reset.isEnabled = manager.shortcut != .defaultShortcut || !manager.isActive
        if let error = manager.error {
            status.stringValue = error + (manager.isActive ? " Your previous shortcut is still active." : " Use the menu bar to open Understudy.")
            status.textColor = .systemOrange
        } else {
            status.stringValue = manager.isRecording
                ? "Press a combination with Command, Option, or Control. Escape cancels. If another app responds, choose a different combination."
                : "Click Record shortcut, then press your new combination. Saved automatically on this Mac. Default: ⌥ Space."
            status.textColor = .secondaryLabelColor
        }
    }

    func windowDidResignKey(_ notification: Notification) { manager.cancelRecording() }
    func windowWillClose(_ notification: Notification) { manager.cancelRecording() }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
