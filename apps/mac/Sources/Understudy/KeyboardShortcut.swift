import AppKit
import Carbon
import Combine

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultShortcut = KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyLabel: "Space")
    /// Opens the quick launcher.
    static let launcherShortcut = KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), keyLabel: "Space")
    static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    var display: String {
        var prefix = ""
        if modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        return prefix + " " + keyLabel
    }

    var validationError: String? {
        guard keyCode <= 127, !keyLabel.isEmpty, keyLabel.count <= 24,
              modifiers & ~Self.modifierMask == 0 else { return "That key combination isn't supported." }
        guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            return "Include Command, Option, or Control with your key."
        }
        guard keyCode != UInt32(kVK_Escape) else { return "Escape is reserved for canceling." }
        if modifiers == UInt32(cmdKey), [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_Comma].contains(Int(keyCode)) {
            return "Choose another combination; that one is a standard app command."
        }
        return nil
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        // Modifier-only presses and media keys aren't usable shortcut keys.
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Forward Delete",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20", 76: "Enter"]
        let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !label.isEmpty, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

struct ShortcutFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Each registration owns its handler and checks its ID before dispatching.
/// Candidate registration happens before the old registration is released.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static var nextID: UInt32 = 0
    private let id: UInt32
    private let action: () -> Void

    init(shortcut: KeyboardShortcut, action: @escaping () -> Void) throws {
        self.action = action
        Self.nextID &+= 1
        id = Self.nextID
        var symbolicKeys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&symbolicKeys) == noErr,
           let keys = symbolicKeys?.takeRetainedValue() as? [[String: Any]] {
            if keys.contains(where: {
                ($0[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
                ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode &&
                ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == shortcut.modifiers
            }) {
                throw ShortcutFailure(message: "That shortcut is enabled in macOS. Choose a different combination.")
            }
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            var pressed = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed) == noErr,
                  pressed.signature == OSType(0x5553_5459), pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { [weak hotKey] in hotKey?.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else { throw ShortcutFailure(message: "Couldn't listen for shortcuts (\(handlerStatus)).") }
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: OSType(0x5553_5459), id: id),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler); self.handler = nil }
            throw ShortcutFailure(message: status == eventHotKeyExistsErr
                ? "That shortcut is already in use. Choose a different combination."
                : "Couldn't register that shortcut (\(status)). Try another combination.")
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class ShortcutManager: ObservableObject {
    typealias Installer = (KeyboardShortcut, @escaping () -> Void) throws -> AnyObject
    static let preferenceKey = "globalShortcut.v1"
    @Published private(set) var shortcut: KeyboardShortcut
    @Published private(set) var isActive = false
    @Published private(set) var isRecording = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let install: Installer
    private var registration: AnyObject?
    private var action: (() -> Void)?

    init(defaults: UserDefaults = .standard, install: @escaping Installer = { try HotKey(shortcut: $0, action: $1) }) {
        self.defaults = defaults
        self.install = install
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data), saved.validationError == nil {
            shortcut = saved
        } else { shortcut = .defaultShortcut }
    }

    func start(action: @escaping () -> Void) {
        self.action = action
        change(to: shortcut)
    }

    func beginRecording() { error = nil; isRecording = true }
    func cancelRecording() { isRecording = false }
    func rejectKey() { error = "Choose a letter, number, punctuation key, or function key with a modifier." }

    @discardableResult
    func change(to candidate: KeyboardShortcut) -> Bool {
        if let reason = candidate.validationError { error = reason; return false }
        do {
            let encoded = try JSONEncoder().encode(candidate)
            // The key label can change with the input language; the physical binding is identical.
            if candidate.keyCode == shortcut.keyCode && candidate.modifiers == shortcut.modifiers && isActive {
                shortcut = candidate
                defaults.set(encoded, forKey: Self.preferenceKey)
                error = nil; isRecording = false
                return true
            }
            let replacement = try install(candidate) { [weak self] in
                guard let self else { return }
                // Recording the existing hotkey must not trigger the notch action.
                if self.isRecording { self.cancelRecording() } else { self.action?() }
            }
            registration = replacement
            shortcut = candidate
            isActive = true
            defaults.set(encoded, forKey: Self.preferenceKey)
            error = nil
            isRecording = false
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
