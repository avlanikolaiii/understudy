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

func snapshot() -> [String: Any] {
    let system = AXUIElementCreateSystemWide()
    var out: [String: Any] = [:]
    guard let appObj = attr(system, kAXFocusedApplicationAttribute) else { return ["focus": "none"] }
    let app = appObj as! AXUIElement
    var pid: pid_t = 0
    AXUIElementGetPid(app, &pid)
    let running = NSRunningApplication(processIdentifier: pid)
    out["app"] = running?.localizedName ?? "pid \(pid)"
    out["bundle"] = running?.bundleIdentifier ?? ""
    if let winObj = attr(app, kAXFocusedWindowAttribute) {
        out["window"] = text(attr(winObj as! AXUIElement, kAXTitleAttribute)) ?? ""
    }
    guard let elObj = attr(system, kAXFocusedUIElementAttribute) else { return out }
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
    if let n = count(attr(el, "AXSelectedCells")) { out["selectedCells"] = n }
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
    print(ok ? "TRUSTED: Accessibility access is on for this process."
             : "NOT TRUSTED: turn on Accessibility for the app that runs this tool (System Settings > Privacy & Security > Accessibility). Launching app: \(parent)")
    exit(ok ? 0 : 2)

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
        Thread.sleep(forTimeInterval: 0.2)
    }
    print("Done: \(lines) changes logged to \(path)")

default:
    print("Usage: ax-capture check | ax-capture record [file] [seconds]")
    exit(64)
}
