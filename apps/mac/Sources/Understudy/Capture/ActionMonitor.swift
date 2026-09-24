import AppKit
import Carbon.HIToolbox
import UnderstudyCore

/// Notes what the person does in other apps while Watch records: which app is in front, what they
/// click (and what it is), what they type and where, shortcuts, and spreadsheet selections.
/// It needs Accessibility access. Nothing typed into a password field is recorded, and macOS
/// withholds keystrokes entirely while secure input is on. Events inside Understudy aren't seen.
@MainActor
final class ActionMonitor {
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var clock: () -> Double = { 0 }
    private var emit: (RecordedAction) -> Void = { _ in }
    private var typed = ""
    private var typedAt = 0.0
    private var typedPid: pid_t = 0
    private var flushTimer: Timer?
    private var lastCells: [pid_t: String] = [:]

    /// Seconds without typing after which the typed text is recorded as one action.
    static let typingPause = 1.5

    func start(clock: @escaping () -> Double, emit: @escaping (RecordedAction) -> Void) {
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

    func stop() {
        flushTyping()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        flushTimer?.invalidate(); flushTimer = nil
        lastCells = [:]
    }

    // MARK: Events

    private func activated(_ app: NSRunningApplication) {
        guard app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
        flushTyping()
        let t = clock(), pid = app.processIdentifier
        // The window title is ready once the app has finished coming forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            emit(RecordedAction(t: t, kind: .appSwitch, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                                window: AX.focusedWindowTitle(pid: pid)))
        }
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
        if modifiers.contains(.command) || modifiers.contains(.control) {
            flushTyping()
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            emit(RecordedAction(t: clock(), kind: .shortcut, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                                window: AX.focusedWindowTitle(pid: pid), text: Self.symbols(modifiers) + key))
            readSelection(pid: pid, after: 0.2)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Delete:
            if !typed.isEmpty { typed.removeLast() }
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
            flushTyping()
            readSelection(pid: pid, after: 0.2)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape:
            flushTyping()
            readSelection(pid: pid, after: 0.2)
        default:
            guard let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
            if typed.isEmpty || typedPid != pid { flushTyping(); typedAt = clock(); typedPid = pid }
            typed += characters
        }
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.typingPause, repeats: false) { _ in
            MainActor.assumeIsolated { self.flushTyping() }
        }
    }

    // MARK: Recording

    /// Records what was typed since the last action as one action, with the field it went into.
    private func flushTyping() {
        flushTimer?.invalidate(); flushTimer = nil
        guard !typed.isEmpty, let app = NSRunningApplication(processIdentifier: typedPid) else { typed = ""; return }
        let field = AX.focusedElement(pid: typedPid)
        emit(RecordedAction(t: typedAt, kind: .typing, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                            window: AX.focusedWindowTitle(pid: typedPid), element: field.map(AX.describe),
                            text: typed, value: field.flatMap { AX.string($0, kAXValueAttribute) }))
        typed = ""
    }

    /// Records a new spreadsheet selection once the app has reacted to a click or key.
    private func readSelection(pid: pid_t, after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            guard !monitors.isEmpty, let cells = AX.selectedCells(pid: pid), cells != lastCells[pid],
                  let app = NSRunningApplication(processIdentifier: pid) else { return }
            lastCells[pid] = cells
            emit(RecordedAction(t: clock(), kind: .selection, app: app.localizedName ?? "App", bundle: app.bundleIdentifier,
                                window: AX.focusedWindowTitle(pid: pid), cells: cells))
        }
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }
}
