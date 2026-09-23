// ax-capture: Understudy capture experiment (M1).
//
// Records what macOS Accessibility exposes while someone works: the focused
// app, window, and element (role, title, value, selection), one JSON line per
// change. It is a measuring tool, not product code. The question it answers is
// whether a demonstration can be captured well enough to know which cells were
// used, and what was typed where.
//
//   ax-capture check                 Is this process allowed to use Accessibility?
//   ax-capture record [file] [secs]  Log changes until Ctrl-C (or for `secs` seconds).
//
// Password fields (AXSecureTextField) are logged by role only, never by value.

import AppKit
import ApplicationServices
import Foundation

setvbuf(stdout, nil, _IONBF, 0)

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func text(_ v: AnyObject?, limit: Int = 240) -> String? {
    guard let v else { return nil }
    var s: String?
    if let str = v as? String { s = str }
    else if let n = v as? NSNumber { s = n.stringValue }
    else if let u = v as? URL { s = u.absoluteString }
    else if CFGetTypeID(v) == AXValueGetTypeID() {
        let axv = v as! AXValue
        var r = CFRange()
        if AXValueGetType(axv) == .cfRange, AXValueGetValue(axv, .cfRange, &r) { s = "range(\(r.location),\(r.length))" }
    }
    guard let s, !s.isEmpty else { return nil }
    return s.count > limit ? String(s.prefix(limit)) + "…" : s
}

func count(_ v: AnyObject?) -> Int? { (v as? [AnyObject])?.count }

func errName(_ e: AXError) -> String {
    switch e {
    case .success: return "success"
    case .apiDisabled: return "apiDisabled"
    case .cannotComplete: return "cannotComplete"
    case .noValue: return "noValue"
    case .attributeUnsupported: return "attributeUnsupported"
    case .notImplemented: return "notImplemented"
    case .invalidUIElement: return "invalidUIElement"
    case .illegalArgument: return "illegalArgument"
    case .failure: return "failure"
    default: return "code \(e.rawValue)"
    }
}

// Owner of the frontmost on-screen normal window. Works without a run loop,
// as a fallback when the system-wide focused-application query fails.
func frontmostPidFromWindowList() -> pid_t? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
        if let pid = w[kCGWindowOwnerPID as String] as? Int32,
           NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular { return pid }
    }
    return nil
}

func snapshot() -> [String: Any] {
    let system = AXUIElementCreateSystemWide()
    var out: [String: Any] = [:]
    var appRef: AnyObject?
    let sysErr = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef)
    var pid: pid_t = 0
    let app: AXUIElement
    if sysErr == .success, let a = appRef {
        app = a as! AXUIElement
        AXUIElementGetPid(app, &pid)
        out["via"] = "systemWide"
    } else if let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular {
        pid = front.processIdentifier
        app = AXUIElementCreateApplication(pid)
        out["via"] = "workspace"
        out["systemWideError"] = errName(sysErr)
    } else if let p = frontmostPidFromWindowList() {
        pid = p
        app = AXUIElementCreateApplication(p)
        out["via"] = "windowList"
        out["systemWideError"] = errName(sysErr)
    } else {
        return ["focus": "none", "systemWideError": errName(sysErr)]
    }
    return out.merging(describe(app: app, pid: pid)) { a, _ in a }
}

func colName(_ i: Int) -> String {
    var n = i + 1, s = ""
    while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
    return s
}

func indexRange(_ el: AXUIElement, _ name: String) -> CFRange? {
    guard let v = attr(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var r = CFRange()
    return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
}

// Finds a spreadsheet-style table under `root` and returns its selected cells as
// "C5=1225" (address from the cell's own row and column indexes, value as exposed).
func tableSelection(_ root: AXUIElement) -> (table: String, cells: [String])? {
    var found: (String, [String])?
    func search(_ el: AXUIElement, _ depth: Int) {
        guard found == nil, depth <= 5 else { return }
        let role = text(attr(el, kAXRoleAttribute)) ?? ""
        if role == "AXTable", let sel = attr(el, "AXSelectedCells") as? [AXUIElement] {
            let cells = sel.prefix(12).map { c -> String in
                let r = indexRange(c, "AXRowIndexRange"), k = indexRange(c, "AXColumnIndexRange")
                let addr = (r != nil && k != nil) ? "\(colName(k!.location))\(r!.location + 1)" : "?"
                return "\(addr)=\(text(attr(c, kAXValueAttribute), limit: 40) ?? "")"
            }
            found = (text(attr(el, kAXTitleAttribute), limit: 60) ?? "table", Array(cells) + (sel.count > 12 ? ["…+\(sel.count - 12)"] : []))
            return
        }
        guard ["AXWindow", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXGroup"].contains(role) else { return }
        if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] { for k in kids.prefix(30) { search(k, depth + 1) } }
    }
    search(root, 0)
    return found
}

// Everything Accessibility exposes about one app's focused window and element.
func describe(app: AXUIElement, pid: pid_t) -> [String: Any] {
    var out: [String: Any] = [:]
    let running = NSRunningApplication(processIdentifier: pid)
    out["app"] = running?.localizedName ?? "pid \(pid)"
    out["bundle"] = running?.bundleIdentifier ?? ""
    if let winObj = attr(app, kAXFocusedWindowAttribute) {
        out["window"] = text(attr(winObj as! AXUIElement, kAXTitleAttribute)) ?? ""
        if let t = tableSelection(winObj as! AXUIElement) {
            out["table"] = t.table
            out["selectedCells"] = t.cells.joined(separator: " ")
        }
    }
    var elRef: AnyObject?
    let elErr = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &elRef)
    guard elErr == .success, let elObj = elRef else { out["elementError"] = errName(elErr); return out }
    let el = elObj as! AXUIElement
    let role = text(attr(el, kAXRoleAttribute)) ?? ""
    out["role"] = role
    if let v = text(attr(el, kAXSubroleAttribute)) { out["subrole"] = v }
    if let v = text(attr(el, kAXRoleDescriptionAttribute)) { out["roleDesc"] = v }
    if let v = text(attr(el, kAXTitleAttribute)) { out["title"] = v }
    if let v = text(attr(el, kAXDescriptionAttribute)) { out["desc"] = v }
    if let v = text(attr(el, kAXHelpAttribute)) { out["help"] = v }
    if role == "AXSecureTextField" || (out["subrole"] as? String) == "AXSecureTextField" {
        out["value"] = "[secure field: not recorded]"
    } else {
        if let v = text(attr(el, kAXValueAttribute)) { out["value"] = v }
        if let v = text(attr(el, kAXSelectedTextAttribute)) { out["selectedText"] = v }
    }
    if let v = text(attr(el, kAXSelectedTextRangeAttribute)) { out["selectedRange"] = v }
    if out["selectedCells"] == nil, let n = count(attr(el, "AXSelectedCells")) { out["selectedCells"] = n }
    if let n = count(attr(el, kAXSelectedRowsAttribute)) { out["selectedRows"] = n }
    if let v = text(attr(el, "AXURL")) { out["url"] = v }
    // Ancestors: shows whether a focused thing sits inside a table, grid, or web area.
    var chain: [String] = []
    var cur: AXUIElement? = el
    for _ in 0..<6 {
        guard let c = cur, let p = attr(c, kAXParentAttribute) else { break }
        let pe = p as! AXUIElement
        let r = text(attr(pe, kAXRoleAttribute)) ?? "?"
        let d = text(attr(pe, kAXDescriptionAttribute), limit: 40) ?? text(attr(pe, kAXTitleAttribute), limit: 40)
        chain.append(d.map { "\(r)[\($0)]" } ?? r)
        cur = pe
    }
    if !chain.isEmpty { out["ancestors"] = chain.joined(separator: " < ") }
    return out
}

func trusted(prompt: Bool) -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "check"

switch cmd {
case "check":
    let ok = trusted(prompt: false)
    let parent = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "unknown"
    if ok {
        let s = snapshot()
        let d = (try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        print("Self-test (what's focused right now): \(d)")
    }
    print(ok ? "TRUSTED: Accessibility access is on for this process."
             : "NOT TRUSTED: turn on Accessibility for the app that runs this tool (System Settings > Privacy & Security > Accessibility). Launching app: \(parent)")
    exit(ok ? 0 : 2)

case "dump":
    // Print an app's accessibility tree (focused window) to a given depth.
    // Usage: ax-capture dump <bundleId> [depth]
    guard trusted(prompt: false), args.count > 2 else { print("Usage: ax-capture dump <bundleId> [depth] (needs Accessibility access)"); exit(64) }
    let maxDepth = args.count > 3 ? Int(args[3]) ?? 6 : 6  // "--enhanced" may follow
    guard let ra = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else { print("Not running: \(args[2])"); exit(1) }
    let appEl = AXUIElementCreateApplication(ra.processIdentifier)
    // Optional: the mode screen readers switch on, which can expose more of an app's UI.
    if args.contains("--enhanced") {
        let e = AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        print("AXEnhancedUserInterface on: \(errName(e))")
        Thread.sleep(forTimeInterval: 1.5)
    }
    defer { if args.contains("--enhanced") { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) } }
    guard let win = attr(appEl, kAXFocusedWindowAttribute) ?? attr(appEl, kAXMainWindowAttribute) else { print("No window"); exit(1) }
    var nodes = 0
    func walk(_ el: AXUIElement, _ depth: Int) {
        guard depth <= maxDepth, nodes < 400 else { return }
        nodes += 1
        var bits: [String] = [text(attr(el, kAXRoleAttribute)) ?? "?"]
        for (k, label) in [(kAXTitleAttribute, "title"), (kAXDescriptionAttribute, "desc"), (kAXValueAttribute, "value")] {
            if let v = text(attr(el, k), limit: 50) { bits.append("\(label)=\"\(v)\"") }
        }
        if let n = count(attr(el, "AXSelectedCells")) { bits.append("selectedCells=\(n)") }
        if let n = count(attr(el, kAXSelectedChildrenAttribute)) { bits.append("selectedChildren=\(n)") }
        if let n = count(attr(el, kAXSelectedRowsAttribute)) { bits.append("selectedRows=\(n)") }
        if let n = count(attr(el, kAXChildrenAttribute)) { bits.append("children=\(n)") }
        print(String(repeating: "  ", count: depth) + bits.joined(separator: " "))
        if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] { for k in kids.prefix(25) { walk(k, depth + 1) } }
    }
    walk(win as! AXUIElement, 0)
    print("(\(nodes) nodes)")
    if args.contains("--enhanced") { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse); print("AXEnhancedUserInterface off") }

case "record-apps":
    // Watch specific apps' focused elements whether or not they are in front.
    // Usage: ax-capture record-apps <file> <seconds> <bundleId,bundleId,...>
    guard trusted(prompt: true), args.count > 4, let secs = Double(args[3]) else {
        print("Usage: ax-capture record-apps <file> <seconds> <bundleId,bundleId,...> (needs Accessibility access)"); exit(64)
    }
    let path = args[2]
    let bundles = args[4].split(separator: ",").map(String.init)
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let fh = FileHandle(forWritingAtPath: path) else { print("Can't write \(path)"); exit(1) }
    signal(SIGINT) { _ in print("\nStopped."); exit(0) }
    print("Watching \(bundles.joined(separator: ", ")) for \(Int(secs))s → \(path)")
    let t0 = Date()
    var last: [String: String] = [:]
    var lines = 0
    while Date().timeIntervalSince(t0) < secs {
        for b in bundles {
            guard let ra = NSRunningApplication.runningApplications(withBundleIdentifier: b).first else { continue }
            var snap = describe(app: AXUIElementCreateApplication(ra.processIdentifier), pid: ra.processIdentifier)
            let key = (try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            if key != last[b] {
                last[b] = key
                snap["t"] = (Date().timeIntervalSince(t0) * 1000).rounded() / 1000
                snap["front"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                if let d = try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys]) {
                    fh.write(d); fh.write("\n".data(using: .utf8)!); lines += 1
                }
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    print("Done: \(lines) changes logged to \(path)")

case "record":
    guard trusted(prompt: true) else {
        FileHandle.standardError.write("Not trusted for Accessibility. Run `ax-capture check` for details.\n".data(using: .utf8)!)
        exit(2)
    }
    let path = args.count > 2 ? args[2] : "runs/capture-\(Int(Date().timeIntervalSince1970)).jsonl"
    let limit = args.count > 3 ? Double(args[3]) : nil
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let fh = FileHandle(forWritingAtPath: path) else { print("Can't write \(path)"); exit(1) }
    signal(SIGINT) { _ in print("\nStopped."); exit(0) }
    print("Recording to \(path). Press Ctrl-C to stop.")
    let t0 = Date()
    var last = ""
    var lines = 0
    while limit == nil || Date().timeIntervalSince(t0) < limit! {
        var snap = snapshot()
        let key = (try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        if key != last {
            last = key
            snap["t"] = (Date().timeIntervalSince(t0) * 1000).rounded() / 1000
            if let d = try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys]) {
                fh.write(d); fh.write("\n".data(using: .utf8)!)
                lines += 1
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    print("Done: \(lines) changes logged to \(path)")

default:
    print("Usage: ax-capture check | ax-capture record [file] [seconds]")
    exit(64)
}
