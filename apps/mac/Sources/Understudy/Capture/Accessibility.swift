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

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// The control a click landed on. A click on a button's label or icon reports the label, so
    /// this walks up to the nearest element a person would name.
    static func control(from element: AXUIElement) -> AXUIElement {
        let controls: Set = ["AXButton", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
                             "AXLink", "AXCell", "AXTextField", "AXTextArea", "AXComboBox", "AXTab", "AXSecureTextField"]
        var current = element
        for _ in 0..<3 {
            if controls.contains(string(current, kAXRoleAttribute) ?? "") { return current }
            guard let parent = attribute(current, kAXParentAttribute) else { break }
            current = parent as! AXUIElement
        }
        return element
    }

    static func describe(_ element: AXUIElement) -> RecordedAction.Element {
        RecordedAction.Element(role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute),
                               title: string(element, kAXTitleAttribute, limit: 80),
                               description: string(element, kAXDescriptionAttribute, limit: 80),
                               identifier: string(element, kAXIdentifierAttribute, limit: 80))
    }

    /// Finds a control in the app's windows and menu bar: by identifier when it has one, otherwise
    /// or by role and name (title or description), the way Watch recorded it. Breadth-first, bounded.
    static func find(in pid: pid_t, role: String?, name: String?, identifier: String?) -> AXUIElement? {
        guard identifier != nil || name != nil else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var queue: [AXUIElement] = []
        if let window = attribute(app, kAXFocusedWindowAttribute) { queue.append(window as! AXUIElement) }
        queue += (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        if let menuBar = attribute(app, kAXMenuBarAttribute) { queue.append(menuBar as! AXUIElement) }
        var visited = 0
        while !queue.isEmpty, visited < 5_000 {
            let element = queue.removeFirst()
            visited += 1
            if let identifier, string(element, kAXIdentifierAttribute, limit: 200) == identifier { return element }
            if let name, role == nil || string(element, kAXRoleAttribute) == role,
               string(element, kAXTitleAttribute, limit: 200) == name || string(element, kAXDescriptionAttribute, limit: 200) == name {
                return element
            }
            queue += (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        }
        return nil
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
