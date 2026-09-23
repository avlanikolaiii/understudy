import AppKit
import Carbon

private final class Token {
    let release: () -> Void
    init(_ release: @escaping () -> Void) { self.release = release }
    deinit { release() }
}

@main
struct ShortcutChecks {
    @MainActor
    static func main() throws {
        let suite = "app.understudy.shortcut-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let replacement = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(controlKey | optionKey), keyLabel: "U")
        var installed: [KeyboardShortcut] = []
        var callbacks: [() -> Void] = []
        var liveTokens = 0
        var reject = false
        let install: ShortcutManager.Installer = { shortcut, callback in
            if reject { throw ShortcutFailure(message: "Taken") }
            // During replacement the old binding must still be alive.
            if installed.count == 1 { precondition(liveTokens == 1) }
            installed.append(shortcut); callbacks.append(callback)
            liveTokens += 1
            return Token { liveTokens -= 1 }
        }
        let manager = ShortcutManager(defaults: defaults, install: install)
        var fired = 0
        manager.start { fired += 1 }
        precondition(manager.isActive && manager.shortcut == .defaultShortcut && liveTokens == 1)
        callbacks.last?()
        precondition(fired == 1)
        manager.beginRecording()
        callbacks.last?()
        precondition(!manager.isRecording && fired == 1)
        manager.beginRecording()
        precondition(!manager.change(to: KeyboardShortcut(keyCode: 0, modifiers: 0, keyLabel: "A")))
        precondition(manager.isRecording && installed.count == 1)
        precondition(!manager.change(to: KeyboardShortcut(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A")))
        precondition(!manager.change(to: KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey), keyLabel: "Q")))
        let savedBeforeFailure = defaults.data(forKey: ShortcutManager.preferenceKey)
        reject = true
        precondition(!manager.change(to: replacement))
        precondition(manager.isActive && manager.shortcut == .defaultShortcut && liveTokens == 1)
        precondition(defaults.data(forKey: ShortcutManager.preferenceKey) == savedBeforeFailure)
        reject = false
        precondition(manager.change(to: replacement))
        precondition(manager.shortcut == replacement && !manager.isRecording && liveTokens == 1)
        precondition(manager.shortcut.display == "⌃⌥ U")
        precondition(ShortcutManager(defaults: defaults, install: install).shortcut == replacement)
        precondition(manager.change(to: replacement) && installed.count == 2)
        let relabeled = KeyboardShortcut(keyCode: replacement.keyCode, modifiers: replacement.modifiers, keyLabel: "Ü")
        precondition(manager.change(to: relabeled) && installed.count == 2)
        precondition(ShortcutManager(defaults: defaults, install: install).shortcut == relabeled)
        precondition(manager.change(to: replacement) && installed.count == 2)
        manager.beginRecording(); manager.cancelRecording()
        precondition(manager.shortcut == replacement && !manager.isRecording)
        precondition(manager.change(to: .defaultShortcut))
        precondition(ShortcutManager(defaults: defaults, install: install).shortcut == .defaultShortcut)
        defaults.set(Data("broken".utf8), forKey: ShortcutManager.preferenceKey)
        precondition(ShortcutManager(defaults: defaults, install: install).shortcut == .defaultShortcut)
        let unavailable = ShortcutManager(defaults: defaults, install: { _, _ in throw ShortcutFailure(message: "Taken") })
        unavailable.start {}
        precondition(!unavailable.isActive && unavailable.error != nil)

        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "u", charactersIgnoringModifiers: "u",
                                    isARepeat: false, keyCode: UInt16(kVK_ANSI_U))!
        precondition(KeyboardShortcut(event: event) == replacement)

        // Exercise the real OS registration path using an uncommon combination.
        // No key events are posted and no permissions are requested.
        let probe = KeyboardShortcut(keyCode: UInt32(kVK_F19), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), keyLabel: "F19")
        var first: HotKey? = try HotKey(shortcut: probe, action: {})
        precondition(first != nil)
        do {
            _ = try HotKey(shortcut: probe, action: {})
            fatalError("Duplicate registration should fail")
        } catch { precondition(error is ShortcutFailure) }
        first = nil
        let reused = try HotKey(shortcut: probe, action: {})
        withExtendedLifetime(reused) {}
        print("PASS: persistence, validation, cancellation, restore, registration failure, atomic remap, event conversion, and real Carbon conflict/release checks")
    }
}
