import AppKit
import ApplicationServices
import UnderstudyCore

/// Reading other apps through the Accessibility API. Adapted from the capture experiment
/// (tools/ax-capture), where each of these reads was measured on Numbers and TextEdit.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's prompt to open Accessibility settings, once per launch at most.
    static func askForTrust() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String, limit: Int = 500) -> String? {
        guard let value = attribute(element, name) else { return nil }
        let text: String?
        if let s = value as? String { text = s } else if let n = value as? NSNumber { text = n.stringValue } else { text = nil }
        guard let text, !text.isEmpty else { return nil }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element)
        return result == .success ? element : nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let p = attribute(element, kAXPositionAttribute), let z = attribute(element, kAXSizeAttribute),
              AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(z as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// True when a hit test returned a large container rather than what was clicked. Apps built on
    /// Chromium answer the first hit test at a point with their whole page, and the exact element
    /// once they've looked (measured on Spotify: the second answer, a moment later, is exact).
    static func isCoarse(_ element: AXUIElement) -> Bool {
        guard let frame = frame(of: element), let window = attribute(element, kAXWindowAttribute).flatMap({ self.frame(of: $0 as! AXUIElement) }),
              window.width * window.height > 0 else { return false }
        return frame.width * frame.height >= 0.3 * window.width * window.height
    }

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// The control a click landed on. A click on a button's label or icon, or on a card's image,
    /// reports that part, so this walks up to the nearest element that can be pressed or that a
    /// person would name as a control.
    static func control(from element: AXUIElement) -> AXUIElement {
        let controls: Set = ["AXButton", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
                             "AXLink", "AXCell", "AXRow", "AXTextField", "AXTextArea", "AXComboBox", "AXTab", "AXSecureTextField"]
        var current = element
        for _ in 0..<6 {
            if controls.contains(string(current, kAXRoleAttribute) ?? "") || canPress(current) { return current }
            guard let parent = attribute(current, kAXParentAttribute) else { break }
            current = parent as! AXUIElement
        }
        return element
    }

    static func canPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success && ((names as? [String]) ?? []).contains(kAXPressAction as String)
    }

    /// Its title or description; for something without one (a song row), the first texts inside it.
    static func name(of element: AXUIElement) -> String? {
        if let own = string(element, kAXTitleAttribute, limit: 80) ?? string(element, kAXDescriptionAttribute, limit: 80) { return own }
        let inside = texts(in: element, limit: 2, nodes: 40)
        return inside.isEmpty ? nil : inside.joined(separator: " · ")
    }

    /// Text around the element that tells it apart from others with the same name: the texts of
    /// its nearest ancestor that has any besides the element's own name. Computed the same way when
    /// recording and when running, so it identifies the element wherever the window is.
    static func context(of element: AXUIElement, name: String?) -> String? {
        var current = element
        for _ in 0..<6 {
            guard let parent = attribute(current, kAXParentAttribute) else { return nil }
            current = parent as! AXUIElement
            let found = texts(in: current, limit: 3, nodes: 80).filter { $0 != name && !(name?.contains($0) ?? false) }
            if !found.isEmpty { return found.prefix(2).joined(separator: " · ") }
        }
        return nil
    }

    /// Visible texts (static text values, link and heading titles) under `root`, breadth-first.
    static func texts(in root: AXUIElement, limit: Int, nodes: Int) -> [String] {
        var queue = [root], found: [String] = [], visited = 0
        while !queue.isEmpty, visited < nodes, found.count < limit {
            let element = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            let text = role == "AXStaticText" ? string(element, kAXValueAttribute, limit: 80)
                : ["AXLink", "AXHeading"].contains(role) ? string(element, kAXTitleAttribute, limit: 80) ?? string(element, kAXDescriptionAttribute, limit: 80) : nil
            if let text, !text.trimmingCharacters(in: .whitespaces).isEmpty, !found.contains(text) { found.append(text) }
            queue += (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        return found
    }

    /// What was clicked, with what finds it again: role, name, identifier, context.
    static func describeClicked(_ element: AXUIElement) -> RecordedAction.Element {
        var described = describe(element)
        let name = self.name(of: element)
        if described.name == nil { described.title = name }
        described.context = context(of: element, name: name)
        described.pressable = canPress(element)
        return described
    }

    // MARK: Apps that hide their contents

    enum Engine { case electron, chromiumEmbedded, other }

    /// Apps built on Chromium hide what's inside their windows unless asked: Electron apps show it
    /// once asked at runtime; apps on the Chromium Embedded Framework (Spotify) only when opened
    /// with --force-renderer-accessibility.
    static func engine(of app: NSRunningApplication) -> Engine {
        guard let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks").path else { return .other }
        if FileManager.default.fileExists(atPath: frameworks + "/Electron Framework.framework") { return .electron }
        if FileManager.default.fileExists(atPath: frameworks + "/Chromium Embedded Framework.framework") { return .chromiumEmbedded }
        return .other
    }

    /// Asks an Electron app to show its contents to Accessibility. Harmless for other apps.
    static func reveal(_ app: NSRunningApplication) {
        guard engine(of: app) == .electron else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// True when the app's front window shows almost nothing to Accessibility (its contents are hidden).
    static func hidesContents(_ app: NSRunningApplication) -> Bool {
        guard engine(of: app) != .other,
              let window = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute) else { return false }
        var queue = [window as! AXUIElement], visited = 0
        while !queue.isEmpty, visited < 60 {
            visited += 1
            queue += (attribute(queue.removeFirst(), kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        return visited < 40
    }

    /// Reopens an app so it shows its contents to Accessibility (Chromium Embedded Framework apps).
    /// The person asks for this from the review; a run does it on its own when a step needs it.
    static func reopenRevealed(bundle: String, done: @escaping (Bool) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return done(false) }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
        running.forEach { $0.terminate() }
        func open(_ attempts: Int) {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty && attempts > 0 {
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open(attempts - 1) }
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--force-renderer-accessibility"]
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
                DispatchQueue.main.async { done(app != nil) }
            }
        }
        open(20)
    }

    static func describe(_ element: AXUIElement) -> RecordedAction.Element {
        RecordedAction.Element(role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute),
                               title: string(element, kAXTitleAttribute, limit: 80),
                               description: string(element, kAXDescriptionAttribute, limit: 80),
                               identifier: string(element, kAXIdentifierAttribute, limit: 80))
    }

    /// Finds a control in the app's windows and menu bar the way Watch recorded it: by identifier,
    /// or by role and name (its title, description, or the texts inside it). When several match
    /// (nine "Play" buttons), the one whose context matches is chosen. Never by position.
    static func find(in pid: pid_t, role: String?, name: String?, identifier: String?, context: String?) -> AXUIElement? {
        guard identifier != nil || name != nil else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var queue: [AXUIElement] = []
        if let window = attribute(app, kAXFocusedWindowAttribute) { queue.append(window as! AXUIElement) }
        queue += (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        if let menuBar = attribute(app, kAXMenuBarAttribute) { queue.append(menuBar as! AXUIElement) }
        var visited = 0, candidates: [AXUIElement] = []
        while !queue.isEmpty, visited < 8_000, candidates.count < 60 {
            let element = queue.removeFirst()
            visited += 1
            if let identifier, string(element, kAXIdentifierAttribute, limit: 200) == identifier {
                candidates.append(element)
            } else if let name, role == nil || string(element, kAXRoleAttribute) == role, self.name(of: element) == name {
                // Compared exactly as it was recorded (same length limit), so long names match too.
                candidates.append(element)
            }
            queue += (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        guard let context, candidates.count > 1 else { return candidates.first }
        return candidates.first { self.context(of: $0, name: name) == context }
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        guard let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return string(window as! AXUIElement, kAXTitleAttribute, limit: 120)
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
    }

    /// Selected cells of a spreadsheet-style table in the app's focused window, as "D5=1200 E5=48".
    static func selectedCells(pid: pid_t) -> String? {
        guard let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        var found: String?
        func search(_ element: AXUIElement, _ depth: Int) {
            guard found == nil, depth <= 5 else { return }
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == "AXTable", let cells = attribute(element, "AXSelectedCells") as? [AXUIElement], !cells.isEmpty {
                found = cells.prefix(24).map { cell in
                    let address = cellAddress(cell) ?? "?"
                    return "\(address)=\(string(cell, kAXValueAttribute, limit: 40) ?? "")"
                }.joined(separator: " ")
                return
            }
            guard ["AXWindow", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXGroup"].contains(role),
                  let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
            for child in children.prefix(30) { search(child, depth + 1) }
        }
        search(window as! AXUIElement, 0)
        return found
    }

    private static func cellAddress(_ cell: AXUIElement) -> String? {
        guard let row = range(cell, "AXRowIndexRange"), let column = range(cell, "AXColumnIndexRange") else { return nil }
        var n = column.location + 1, letters = ""
        while n > 0 { let r = (n - 1) % 26; letters = String(UnicodeScalar(65 + r)!) + letters; n = (n - 1) / 26 }
        return "\(letters)\(row.location + 1)"
    }

    private static func range(_ element: AXUIElement, _ name: String) -> CFRange? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }
}
