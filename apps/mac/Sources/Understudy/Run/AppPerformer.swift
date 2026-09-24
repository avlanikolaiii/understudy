import AppKit
import Carbon.HIToolbox
import UnderstudyCore

/// Performs recorded steps on this Mac without moving the mouse: it opens apps, presses controls
/// by their name through Accessibility, clicks into fields, types, and presses keys. Each step
/// says how it was checked. It needs Accessibility access (the same as Watch).
@MainActor
final class AppPerformer: StepPerformer {
    private var cancelled = false

    static let accessibilityNeeded = "Understudy needs Accessibility access to run skills. "
        + "Turn on Understudy in System Settings → Privacy & Security → Accessibility."

    func perform(_ step: SkillDefinition.Step, done: @escaping (StepOutcome) -> Void) {
        cancelled = false
        guard AX.isTrusted else { return done(StepOutcome(.blocked, .none, Self.accessibilityNeeded)) }
        switch step.parameters["action"] {
        case "activate": activate(step, done)
        case "press", "focus": act(on: step, done)
        case "waitText", "waitSeconds": wait(step, done)
        case "open": open(step, done)
        case "type": type(step, done)
        case "keys": keys(step, done)
        default: done(StepOutcome(.blocked, .none, step.parameters["reason"] ?? "This step can't run yet."))
        }
    }

    func cancel() { cancelled = true }

    // MARK: Steps

    private func activate(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let name = step.parameters["app"] ?? "the app"
        guard let url = Self.appURL(bundle: step.target.app, name: name) else {
            return done(StepOutcome(.failed, .none, "Couldn't find \(name) on this Mac."))
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async { [self] in
                guard let app, error == nil else {
                    return done(StepOutcome(.failed, .none, "\(name) didn't open: \(error?.localizedDescription ?? "unknown error")."))
                }
                app.activate()
                AX.reveal(app)
                poll { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier } then: { inFront in
                    guard inFront else { return done(StepOutcome(.failed, .none, "\(name) opened but didn't come to the front.")) }
                    // An app that hides its buttons (e.g. Spotify) is reopened so the next steps can find them.
                    guard AX.engine(of: app) == .chromiumEmbedded, AX.hidesContents(app), let bundle = app.bundleIdentifier else {
                        return done(StepOutcome(.done, .verified, "\(name) is in front."))
                    }
                    AX.reopenRevealed(bundle: bundle) { reopened in
                        guard reopened else { return done(StepOutcome(.failed, .none, "\(name) couldn't be reopened so Understudy can see its buttons.")) }
                        self.poll { NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first.map { !AX.hidesContents($0) && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle } ?? false } then: { ready in
                            done(ready ? StepOutcome(.done, .verified, "\(name) is in front, reopened so Understudy can see its buttons.")
                                       : StepOutcome(.failed, .none, "\(name) was reopened but still hides its buttons."))
                        }
                    }
                }
            }
        }
    }

    private func act(on step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let label = step.target.title ?? step.target.identifier ?? "the control"
        // Pressing through Accessibility works whether or not the app is in front.
        guard let app = step.target.app.flatMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
                ?? frontApp(for: step) else {
            return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") isn't open."))
        }
        let pid = app.processIdentifier, context = step.parameters["context"]
        // Waits for the control to appear (up to the step's timeout) instead of a fixed pause.
        var located = AX.Located.missing
        poll({
            located = AX.locate(in: pid, role: step.target.role, name: step.target.title, identifier: step.target.identifier, context: context)
            if case .exact = located { return true }
            return false
        }, timeout: Self.timeout(step)) { [self] _ in
            let element: AXUIElement, note: String
            switch located {
            case .exact(let found): element = found; note = ""
            case .similar(let found, let name): element = found; note = " Found by a similar name: \(RecordedAction.quote(name))."
            case .ambiguous(let count):
                return done(StepOutcome(.blocked, .none, "\(count) controls look like \(RecordedAction.quote(label)); Understudy doesn't guess which."))
            case .missing:
                // A toggle showing its other state ("Pause" where "Play" was recorded) means the
                // step's result is already there: nothing to press.
                if let name = step.target.title, let other = Self.toggles[name],
                   AX.find(in: pid, role: step.target.role, name: other, identifier: nil, context: context) != nil {
                    return done(StepOutcome(.done, .verified, "\(RecordedAction.quote(other)) is showing, so it's already done; nothing was pressed."))
                }
                return done(StepOutcome(.failed, .none, "Couldn't find \(RecordedAction.quote(label)) in \(app.localizedName ?? "the app") within \(Int(Self.timeout(step))) s."))
            }
            AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
            if step.parameters["action"] == "focus" {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                let focused = AX.focusedElement(pid: pid).map { CFEqual($0, element) } ?? false
                return done(focused ? StepOutcome(.done, .verified, "The cursor is in \(RecordedAction.quote(label)).\(note)")
                                    : StepOutcome(.done, .notVerifiable, "Clicked into \(RecordedAction.quote(label)); focus couldn't be read back.\(note)"))
            }
            // Pressed through Accessibility, wherever it is on screen; a double-click presses twice.
            let before = AX.landmarks(pid: pid)
            let times = Int(step.parameters["clicks"] ?? "1") ?? 1
            var result = AXUIElementPerformAction(element, kAXPressAction as CFString)
            if times > 1, result == .success { usleep(80_000); result = AXUIElementPerformAction(element, kAXPressAction as CFString) }
            guard result == .success else { return done(StepOutcome(.failed, .none, "\(RecordedAction.quote(label)) couldn't be pressed.\(note)")) }
            let what = times > 1 ? "Double-clicked" : "Pressed"
            // Then read back what changed: a toggle's other state, or a heading or title with its name.
            let other = step.target.title.flatMap { Self.toggles[$0] }
            var shown: String?
            poll({
                if let other, AX.find(in: pid, role: step.target.role, name: other, identifier: nil, context: context) != nil {
                    shown = "\(RecordedAction.quote(other)) is showing"; return true
                }
                if let name = step.target.title, Matching.appeared(after: name, before: before, after: AX.landmarks(pid: pid)) {
                    shown = "\(RecordedAction.quote(Matching.keyword(name))) opened"; return true
                }
                return false
            }, timeout: 3) { _ in
                done(shown.map { StepOutcome(.done, .verified, "\(what) \(RecordedAction.quote(label)): \($0).\(note)") }
                     ?? StepOutcome(.done, .notVerifiable, "\(what) \(RecordedAction.quote(label)). What it did can't be read back.\(note)"))
            }
        }
    }

    /// "Wait until" steps: a text shows in the app, or some seconds pass.
    private func wait(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        if step.parameters["action"] == "waitSeconds" {
            let seconds = Double(step.parameters["seconds"] ?? "") ?? 1
            return DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                done(StepOutcome(.done, .none, "Waited \(Int(seconds)) s."))
            }
        }
        let text = step.parameters["text"] ?? ""
        guard !text.isEmpty, let app = step.target.app.flatMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first })
                ?? NSWorkspace.shared.frontmostApplication else {
            return done(StepOutcome(.failed, .none, "Nothing to wait for."))
        }
        poll({ AX.shows(text, pid: app.processIdentifier) }, timeout: Self.timeout(step)) { shown in
            done(shown ? StepOutcome(.done, .verified, "\(RecordedAction.quote(text)) shows in \(app.localizedName ?? "the app").")
                       : StepOutcome(.failed, .none, "\(RecordedAction.quote(text)) didn't show within \(Int(Self.timeout(step))) s."))
        }
    }

    /// "Open a link or file": a web or app link (spotify:…) or a path, in its default app.
    private func open(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let link = (step.parameters["link"] ?? "").trimmingCharacters(in: .whitespaces)
        let url = link.hasPrefix("/") || link.hasPrefix("~") ? URL(fileURLWithPath: (link as NSString).expandingTildeInPath) : URL(string: link)
        guard let url, url.scheme != nil else { return done(StepOutcome(.failed, .none, "\(RecordedAction.quote(link)) isn't a link or a file path.")) }
        guard url.scheme != "file" || FileManager.default.fileExists(atPath: url.path) else {
            return done(StepOutcome(.failed, .none, "\(url.path) doesn't exist."))
        }
        let opener = NSWorkspace.shared.urlForApplication(toOpen: url)
        guard NSWorkspace.shared.open(url) else { return done(StepOutcome(.failed, .none, "macOS couldn't open \(RecordedAction.quote(link)).")) }
        // Verified when the app that opens it comes to the front.
        let bundle = opener.flatMap { Bundle(url: $0)?.bundleIdentifier }
        poll({ bundle != nil && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle }, timeout: 5) { inFront in
            done(inFront ? StepOutcome(.done, .verified, "Opened \(RecordedAction.quote(link)) in \(opener?.deletingPathExtension().lastPathComponent ?? "its app").")
                         : StepOutcome(.done, .notVerifiable, "Asked macOS to open \(RecordedAction.quote(link))."))
        }
    }

    /// How long a step waits for what it needs: its own timeout, or 10 s.
    static func timeout(_ step: SkillDefinition.Step) -> Double { Double(step.parameters["timeout"] ?? "") ?? 10 }

    private func type(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        bringToFront(step) { [self] app in
            guard let app else { return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") couldn't be brought to the front.")) }
            typeText(step, app, done)
        }
    }

    private func typeText(_ step: SkillDefinition.Step, _ app: NSRunningApplication, _ done: @escaping (StepOutcome) -> Void) {
        let text = step.parameters["text"] ?? ""
        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        // Unicode key events carry text directly, so any language and symbol types as recorded.
        for start in stride(from: 0, to: units.count, by: 16) {
            let chunk = Array(units[start..<min(start + 16, units.count)])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event?.post(tap: .cghidEventTap)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let value = AX.focusedElement(pid: app.processIdentifier).flatMap { AX.string($0, kAXValueAttribute, limit: 100_000) }
            done(value?.contains(text) == true ? StepOutcome(.done, .verified, "The field now contains \(RecordedAction.quote(text)).")
                                               : StepOutcome(.done, .notVerifiable, "Typed \(RecordedAction.quote(text)); the field couldn't be read back."))
        }
    }

    private func keys(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let keys = step.parameters["keys"] ?? ""
        // The recorded key code when there is one; otherwise the key named in `keys`.
        let exact = step.parameters["keyCode"].flatMap(Int.init).map { (CGKeyCode($0), Self.flags(in: keys)) }
        guard let (code, flags) = exact ?? Self.keyCode(for: keys) else {
            return done(StepOutcome(.failed, .none, "Understudy can't press \(keys) yet."))
        }
        bringToFront(step) { app in
            guard app != nil else { return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") couldn't be brought to the front.")) }
            let field = app.flatMap { AX.focusedElement(pid: $0.processIdentifier) }
            let before = field.flatMap { AX.string($0, kAXValueAttribute, limit: 10_000) }
            Self.post(code, flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // ↩ in a field that had text: it's submitted when the text changes or clears.
                if keys == "↩", let field, let before, !before.isEmpty, AX.string(field, kAXValueAttribute, limit: 10_000) != before {
                    return done(StepOutcome(.done, .verified, "Pressed ↩; the field was submitted."))
                }
                done(StepOutcome(.done, .notVerifiable, "Pressed \(keys). What it did can't be read back."))
            }
        }
    }

    private static func post(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Keys and typing go to the app in front: if the step's app isn't, bring it forward first.
    private func bringToFront(_ step: SkillDefinition.Step, then: @escaping (NSRunningApplication?) -> Void) {
        if let front = frontApp(for: step) { return then(front) }
        guard let bundle = step.target.app, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            return then(nil)
        }
        app.activate()
        poll { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier } then: { inFront in
            then(inFront ? app : nil)
        }
    }

    /// Controls that show their other state after they're pressed.
    static let toggles = ["Play": "Pause", "Pause": "Play", "Mute": "Unmute", "Unmute": "Mute"]

    // MARK: Helpers

    /// The app the step acts on, if it's in front. Keys and typing go to the front app only.
    private func frontApp(for step: SkillDefinition.Step) -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return nil }
        if let bundle = step.target.app, front.bundleIdentifier != bundle { return nil }
        return front
    }

    /// Checks `condition` every 0.25 s until it holds or the timeout passes, then calls `then`.
    private func poll(_ condition: @escaping () -> Bool, timeout: Double = 5, then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if cancelled { return }
            if condition() { return then(true) }
            if Date() > deadline { return then(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { check() }
        }
        check()
    }

    static func appURL(bundle: String?, name: String) -> URL? {
        if let bundle, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return url }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) { return running.bundleURL }
        let folders = ["/Applications", "/System/Applications", "/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        return folders.map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The modifiers at the start of "⇧⌘K".
    static func flags(in keys: String) -> CGEventFlags {
        var flags: CGEventFlags = []
        for character in keys.dropLast() {
            switch character {
            case "⌃": flags.insert(.maskControl)
            case "⌥": flags.insert(.maskAlternate)
            case "⇧": flags.insert(.maskShift)
            case "⌘": flags.insert(.maskCommand)
            default: return flags
            }
        }
        return flags
    }

    /// "⇧⌘K" → the K key with Shift and Command. Named keys are the symbols Watch records.
    static func keyCode(for keys: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        var rest = Substring(keys)
        let modifiers: [(Character, CGEventFlags)] = [("⌃", .maskControl), ("⌥", .maskAlternate), ("⇧", .maskShift), ("⌘", .maskCommand)]
        while let first = rest.first, let flag = modifiers.first(where: { $0.0 == first })?.1, rest.count > 1 {
            flags.insert(flag); rest = rest.dropFirst()
        }
        let named: [String: Int] = ["↩": kVK_Return, "⇥": kVK_Tab, "⎋": kVK_Escape, "←": kVK_LeftArrow, "→": kVK_RightArrow,
                                    "↑": kVK_UpArrow, "↓": kVK_DownArrow, "⌫": kVK_Delete, "⌦": kVK_ForwardDelete, " ": kVK_Space]
        if let code = named[String(rest)] ?? letters[String(rest).uppercased()] { return (CGKeyCode(code), flags) }
        return nil
    }

    private static let letters: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G,
        "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N,
        "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U,
        "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6,
        "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
        "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
    ]
}
