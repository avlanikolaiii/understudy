import AppKit
import Carbon.HIToolbox
import UnderstudyCore

/// Performs recorded steps on this Mac without moving the mouse: it opens apps, presses controls
/// by their name through Accessibility, clicks into fields, types, and presses keys. Each step
/// says how it was checked. It needs Accessibility access (the same as Watch).
@MainActor
final class AppPerformer: StepPerformer {
    /// How long a step waits for its app or control to appear.
    static let timeout = 5.0
    private var cancelled = false

    static let accessibilityNeeded = "Understudy needs Accessibility access to run skills. "
        + "Turn on Understudy in System Settings → Privacy & Security → Accessibility."

    func perform(_ step: SkillDefinition.Step, done: @escaping (StepOutcome) -> Void) {
        cancelled = false
        guard AX.isTrusted else { return done(StepOutcome(.blocked, .none, Self.accessibilityNeeded)) }
        switch step.parameters["action"] {
        case "activate": activate(step, done)
        case "press", "focus": act(on: step, done)
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
                poll { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier } then: { inFront in
                    done(inFront ? StepOutcome(.done, .verified, "\(name) is in front.")
                                 : StepOutcome(.failed, .none, "\(name) opened but didn't come to the front."))
                }
            }
        }
    }

    private func act(on step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let label = step.target.title ?? step.target.identifier ?? "the control"
        guard let app = frontApp(for: step) else {
            return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") isn't in front."))
        }
        var found: AXUIElement?
        poll({ found = AX.find(in: app.processIdentifier, role: step.target.role, name: step.target.title,
                               identifier: step.target.identifier); return found != nil }) { _ in
            guard let element = found else {
                return done(StepOutcome(.failed, .none, "Couldn't find \(RecordedAction.quote(label)) in \(app.localizedName ?? "the app")."))
            }
            if step.parameters["action"] == "focus" {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                let focused = AX.focusedElement(pid: app.processIdentifier).map { CFEqual($0, element) } ?? false
                done(focused ? StepOutcome(.done, .verified, "The cursor is in \(RecordedAction.quote(label)).")
                             : StepOutcome(.done, .notVerifiable, "Clicked into \(RecordedAction.quote(label)); focus couldn't be read back."))
            } else {
                let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
                done(result == .success ? StepOutcome(.done, .notVerifiable, "Pressed \(RecordedAction.quote(label)). What it did can't be read back.")
                                        : StepOutcome(.failed, .none, "\(RecordedAction.quote(label)) couldn't be pressed."))
            }
        }
    }

    private func type(_ step: SkillDefinition.Step, _ done: @escaping (StepOutcome) -> Void) {
        let text = step.parameters["text"] ?? ""
        guard let app = frontApp(for: step) else {
            return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") isn't in front."))
        }
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
        guard let (code, flags) = Self.keyCode(for: keys) else {
            return done(StepOutcome(.failed, .none, "Understudy can't press \(keys) yet."))
        }
        guard frontApp(for: step) != nil else {
            return done(StepOutcome(.failed, .none, "\(step.parameters["app"] ?? "The app") isn't in front."))
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            done(StepOutcome(.done, .notVerifiable, "Pressed \(keys). What it did can't be read back."))
        }
    }

    // MARK: Helpers

    /// The app the step acts on, if it's in front. Keys and typing go to the front app only.
    private func frontApp(for step: SkillDefinition.Step) -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return nil }
        if let bundle = step.target.app, front.bundleIdentifier != bundle { return nil }
        return front
    }

    /// Checks `condition` every 0.25 s until it holds or the timeout passes, then calls `then`.
    private func poll(_ condition: @escaping () -> Bool, then: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(Self.timeout)
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
