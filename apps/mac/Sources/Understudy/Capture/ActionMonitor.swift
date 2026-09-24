import AppKit
import Carbon.HIToolbox
import UnderstudyCore

/// Notes what the person does in other apps while Watch records: which app is in front, what they
/// click (and what it is), what they type and where, keys and shortcuts, and spreadsheet selections.
/// It needs Accessibility access. Nothing typed into a password field is recorded, and macOS
/// withholds keystrokes entirely while secure input is on. Events inside Understudy aren't seen.
@MainActor
final class ActionMonitor {
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var clock: () -> Double = { 0 }
    private var emit: (RecordedAction) -> Void = { _ in }
    /// Changes on every start and stop, so a delayed read from an earlier take is dropped.
    private var take = 0
    private var typing: Typing?
    private var flushTimer: Timer?
    private var lastCells: [pid_t: String] = [:]
    /// Apps whose spreadsheet selection is read shortly after a click or key; read at once on stop.
    private var pendingSelections: Set<pid_t> = []

    /// Text typed into one field. The field is fixed when typing starts, so a later change of
    /// focus can't move the text to another field, or out of a password field.
    private struct Typing {
        let pid: pid_t
        let app: NSRunningApplication
        let field: AXUIElement?
        let element: RecordedAction.Element?
        let window: String?
        let t: Double
        var text = ""
    }

    /// Seconds without typing after which the typed text is recorded as one action.
    static let typingPause = 1.5

    func start(clock: @escaping () -> Double, emit: @escaping (RecordedAction) -> Void) {
        take += 1
        self.clock = clock
        self.emit = emit
        // Global monitors call back on the main thread.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { self.clicked(at: NSEvent.mouseLocation) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            MainActor.assumeIsolated { self.keyDown(event) }
        }) { monitors.append(monitor) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app { self.activated(app) } }
        })
    }

    /// Records what is still pending (typing, a selection about to be read), then stops listening.
    func stop() {
        flushTyping()
        for pid in pendingSelections { recordSelection(pid: pid) }
        pendingSelections = []
        take += 1
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        lastCells = [:]
    }

    // MARK: Events

    private func activated(_ app: NSRunningApplication) {
        guard app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
        flushTyping()
        emit(RecordedAction(t: clock(), kind: .appSwitch, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                            window: AX.focusedWindowTitle(pid: app.processIdentifier)))
    }

    private func clicked(at location: NSPoint) {
        flushTyping()
        // Accessibility measures from the top-left of the main screen; AppKit from the bottom-left.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        guard let hit = AX.element(at: CGPoint(x: location.x, y: top - location.y)) else { return }
        let pid = AX.pid(of: hit)
        guard pid != getpid(), let app = NSRunningApplication(processIdentifier: pid) else { return }
        emit(RecordedAction(t: clock(), kind: .click, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                            window: AX.focusedWindowTitle(pid: pid), element: AX.describe(AX.control(from: hit))))
        readSelection(pid: pid, after: 0.35)
    }

    private func keyDown(_ event: NSEvent) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let pid = app.processIdentifier
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let named = Self.keyNames[Int(event.keyCode)]
        // Keys go to a text field only if one has focus. Anywhere else (an inbox, a list) a letter
        // is a shortcut, like E to archive: it's recorded as a key press, never as typed text.
        let inTextField = typing?.pid == pid || AX.focusedElement(pid: pid).map(AX.describe)?.isTextInput == true
        if modifiers.contains(.command) || modifiers.contains(.control) || named != nil || !inTextField {
            // A plain backspace while typing corrects the text being typed. Any other deletion
            // (⌥⌫ for a word, or backspacing into text that was already there) is kept as a key.
            if Int(event.keyCode) == kVK_Delete && modifiers.isEmpty && typing?.text.isEmpty == false {
                typing?.text.removeLast()
                return scheduleFlush()
            }
            // A key like Return, Tab, or an arrow, a shortcut, or a key outside a text field:
            // it's replayed as pressed.
            flushTyping()
            let key = named ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
            emit(RecordedAction(t: clock(), kind: .shortcut, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                                window: AX.focusedWindowTitle(pid: pid), text: Self.symbols(modifiers) + key,
                                keyCode: Int(event.keyCode)))
            readSelection(pid: pid, after: 0.2)
            return
        }
        guard let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
        // A new field (even in the same app, e.g. a form that moves to the next field by itself)
        // starts a new typing action, so each text is tied to the field it went into.
        let field = AX.focusedElement(pid: pid)
        let sameField = typing.map { $0.pid == pid && Self.same($0.field, field) } ?? false
        if !sameField {
            flushTyping()
            typing = Typing(pid: pid, app: app, field: field, element: field.map(AX.describe),
                            window: AX.focusedWindowTitle(pid: pid), t: clock())
        }
        typing?.text += characters
        scheduleFlush()
    }

    private static func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): CFEqual(a, b)
        default: false
        }
    }

    // MARK: Recording

    private func scheduleFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.typingPause, repeats: false) { _ in
            MainActor.assumeIsolated { self.flushTyping() }
        }
    }

    /// Records what was typed since the last action as one action, with the field it went into.
    private func flushTyping() {
        flushTimer?.invalidate(); flushTimer = nil
        guard let typing, !typing.text.isEmpty else { self.typing = nil; return }
        self.typing = nil
        // The init redacts text and value when the field is a password field.
        emit(RecordedAction(t: typing.t, kind: .typing, app: typing.app.localizedName ?? "App",
                            bundle: typing.app.bundleIdentifier, window: typing.window, element: typing.element,
                            text: typing.text, value: typing.field.flatMap { AX.string($0, kAXValueAttribute) }))
    }

    /// Records a new spreadsheet selection once the app has reacted to a click or key.
    private func readSelection(pid: pid_t, after seconds: Double) {
        pendingSelections.insert(pid)
        let current = take
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            guard take == current, pendingSelections.remove(pid) != nil else { return }
            // Anything typed before it is recorded first, so actions stay in the order they happened.
            flushTyping()
            recordSelection(pid: pid)
        }
    }

    private func recordSelection(pid: pid_t) {
        guard let cells = AX.selectedCells(pid: pid), cells != lastCells[pid],
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        lastCells[pid] = cells
        emit(RecordedAction(t: clock(), kind: .selection, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                            window: AX.focusedWindowTitle(pid: pid), cells: cells))
    }

    /// Keys recorded by name so a run can press them again.
    static let keyNames: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    ]

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }
}
