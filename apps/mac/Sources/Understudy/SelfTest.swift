import AppKit

/// `--self-test[=SESSIONS,SEED] [--self-test-out=DIR]`
///
/// Runs the real app objects through simulated user sessions: random walks over the flow graph
/// (`qa/flows.json`), checking documented behavior after every step. It also renders every page,
/// Teach step, and notch state to PNG. Uses a temporary library file and no server, like a fresh
/// Mac, and never registers the global shortcut. Writes `self-test.json` and exits 0 (pass) or 1.
struct SelfTestOptions {
    let sessions: Int
    let seed: UInt64
    let out: URL
    let libraryFile: LocalLibraryFile
    let clock = TestClock()

    init?(arguments: [String]) {
        guard let flag = arguments.first(where: { $0 == "--self-test" || $0.hasPrefix("--self-test=") }) else { return nil }
        let parts = flag.split(separator: "=", maxSplits: 1).dropFirst().first?.split(separator: ",") ?? []
        sessions = parts.first.flatMap { Int($0) } ?? 200
        seed = parts.dropFirst().first.flatMap { UInt64($0) } ?? 1
        let outArg = arguments.first(where: { $0.hasPrefix("--self-test-out=") })?.dropFirst("--self-test-out=".count)
        out = URL(fileURLWithPath: outArg.map(String.init) ?? NSTemporaryDirectory() + "understudy-self-test")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-self-test-\(UUID().uuidString)")
        libraryFile = LocalLibraryFile(url: dir.appendingPathComponent("library.json"))
    }

    /// Screen captures run the notch at real speed. Simulated sessions run it 1,000× faster,
    /// except the strips people read (New skill, Receipt), which run 10× faster so they can be observed.
    var sleep: (Double) async -> Void {
        { [clock] seconds in
            let scaled = clock.fast ? (seconds > 2 ? seconds / 10 : seconds / 1000) : seconds
            try? await Task.sleep(nanoseconds: UInt64(scaled * 1_000_000_000))
        }
    }
}

final class TestClock {
    var time: TimeInterval = 1_000
    var fast = false
    func now() -> TimeInterval { time }
}

private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
    mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }
}

@MainActor
final class SelfTest {
    private let app: AppDelegate
    private let options: SelfTestOptions
    private var rng: SplitMix64
    private var nodes: [String: Int] = [:]
    private var edges: [String: Int] = [:]
    private var failures: [[String: Any]] = []
    private var trail: [String] = []
    private var snapshots: [String] = []
    private var session = 0
    private var steps = 0

    init(app: AppDelegate, options: SelfTestOptions) {
        self.app = app
        self.options = options
        rng = SplitMix64(state: options.seed)
    }

    private let names = ["Weekly client update", "  Monthly report  ", "", "   ", "Informe semanal · Casa Lumen",
                         String(repeating: "Long name ", count: 20), "😀 Emoji skill", "Norte"]
    private let clients = ["Norte Studio", "", "Casa Lumen", "  Faro  ", "Client with a very long name that keeps going"]
    private let notes = ["Never estimate missing spend.", "", "   ", "Ask me first if a number is missing.",
                         "Write CTR, never click rate.", "Never estimate missing spend.", "Línea con acentos"]

    // MARK: Run

    func run() async -> Int32 {
        let started = Date()
        try? FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
        await pump(300)
        await captureEveryScreen()
        options.clock.fast = true
        for index in 0..<options.sessions {
            session = index
            trail = []
            for _ in 0..<rng.int(8...40) {
                await step()
                if failures.count >= 50 { break }
            }
            if failures.count >= 50 { break }
        }
        let report: [String: Any] = [
            "seed": options.seed, "sessions": options.sessions, "steps": steps,
            "durationSeconds": Int(Date().timeIntervalSince(started)),
            "nodes": nodes, "edges": edges, "failures": failures, "snapshots": snapshots,
        ]
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: options.out.appendingPathComponent("self-test.json"))
        print("self-test: \(options.sessions) sessions, \(steps) steps, \(nodes.count) nodes, \(edges.count) edges, \(failures.count) failures")
        return failures.isEmpty ? 0 : 1
    }

    // MARK: Screens

    private func captureEveryScreen() async {
        app.openWorkspace()
        for page in PrototypePage.allCases where page != .teach {
            app.ui.page = page
            await pump(250)
            snapshot(mainWindow, name: "page-\(page.rawValue)")
        }
        app.ui.page = .teach
        app.ui.teachingStep = 0
        await pump(250)
        snapshot(mainWindow, name: "teach-1-describe")
        app.ui.startWatch(app.watch)
        advance(12)
        await pump(settle)
        snapshot(mainWindow, name: "teach-2-show")
        snapshot(notchWindow, name: "notch-watching")
        app.watch.stop()
        await pump(settle)
        snapshot(notchWindow, name: "notch-stopped")
        app.ui.reviewWatch(app.watch)
        await pump(250)
        snapshot(mainWindow, name: "teach-3-review")
        app.ui.saveReviewedSkill(library: app.library, watch: app.watch, activity: app.activity)
        await pump(settle)
        snapshot(notchWindow, name: "notch-learned")
        await waitUntil(6) { self.app.activity.mode == .idle }
        app.ui.scenario = .missing
        app.ui.rehearseActiveSkill(library: app.library, activity: app.activity)
        await pump(settle)
        snapshot(notchWindow, name: "notch-rehearsing")
        await waitUntil(8) { self.app.activity.mode == .receipt }
        await pump(settle)
        snapshot(notchWindow, name: "notch-receipt")
        await pump(200)
        snapshot(mainWindow, name: "page-Receipts-after-rehearsal")
        app.activity.dismiss()
        app.activity.playDemo()
        await pump(3_500)
        snapshot(notchWindow, name: "notch-demo")
        app.activity.dismiss()
        await pump(settle * 2)
        snapshot(notchWindow, name: "notch-idle")
        app.openSettings()
        await pump(250)
        checkSettingsWindow()
        NSApp.windows.first { $0.title == "Understudy Settings" }?.performClose(nil)
        app.ui.page = .home
        await pump(150)
    }

    /// Long enough for the notch spring (0.5 s) and row fades (0.35 s) to finish.
    private let settle: Double = 1_200

    /// The settings window is plain AppKit, and copying its views to a bitmap ignores its dark
    /// appearance, so it's checked by structure instead of pixels: visible, in the app's appearance,
    /// with its heading, current shortcut, and both buttons titled.
    private func checkSettingsWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "Understudy Settings" }), let content = window.contentView else {
            return fail("settings.renders", "the settings window didn't open")
        }
        var texts: [String] = []
        func walk(_ view: NSView) {
            if let button = view as? NSButton { texts.append(button.title) } else if let field = view as? NSTextField { texts.append(field.stringValue) }
            view.subviews.forEach(walk)
        }
        walk(content)
        let complete = ["Keyboard shortcut", "Record shortcut", "Restore default"].allSatisfy(texts.contains)
            && texts.contains { $0.contains("Space") || $0.contains("⌥") || $0.contains("⌘") || $0.contains("⌃") }
        expect(window.isVisible && window.effectiveAppearance.name == NSApp.effectiveAppearance.name && complete,
               "settings.renders", "settings must be visible, match the app's appearance, and show its heading, shortcut, and buttons: \(texts)")
        visit("screen.window-settings")
    }

    private var mainWindow: NSWindow? { NSApp.windows.first { $0.title == "Understudy" && !($0 is NotchPanel) } }
    private var notchWindow: NSWindow? { NSApp.windows.first { $0 is NotchPanel } }

    private func snapshot(_ window: NSWindow?, name: String) {
        if window is NotchPanel {
            guard let rep = app.notch.render() else { return fail("screen.renders", "\(name): the notch didn't render") }
            return finishSnapshot(rep, name: name)
        }
        guard let view = window?.contentView, view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fail("screen.renders", "\(name): no window to render")
            return
        }
        // Draw the view in its window's appearance, as AppKit does on screen.
        (window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        // Paint the window's own background (in its appearance) under the view, as on screen.
        // Without it, light text on a dark-mode window lands on transparent pixels.
        if let window, let composed = rep.copy() as? NSBitmapImageRep {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composed)
            // Draw in points (the rep's size), not pixels, or Retina captures come out at 2× and cropped.
            let bounds = NSRect(origin: .zero, size: rep.size)
            // Resolve the dynamic background color in the window's own appearance (dark or light).
            var background = NSColor.clear
            window.effectiveAppearance.performAsCurrentDrawingAppearance {
                background = (window.isOpaque ? window.backgroundColor : .clear).usingColorSpace(.deviceRGB) ?? .clear
            }
            background.setFill()
            bounds.fill()
            rep.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()
            return finishSnapshot(composed, name: name)
        }
        finishSnapshot(rep, name: name)
    }

    private func finishSnapshot(_ rep: NSBitmapImageRep, name: String) {
        // A rendered screen has content: more than a handful of distinct colors.
        var colors = Set<UInt32>()
        let stepX = max(rep.pixelsWide / 40, 1), stepY = max(rep.pixelsHigh / 40, 1)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    colors.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
                }
            }
        }
        if colors.count < 3 { fail("screen.renders", "\(name): rendered blank (\(colors.count) colors)") }
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: options.out.appendingPathComponent("\(name).png"))
            snapshots.append(name)
        }
        visit("screen.\(name)")
    }

    // MARK: One simulated user action

    /// One user action, chosen only among what the real interface offers right now.
    /// Preconditions mirror the UI: a control is only used while it is on screen and enabled.
    private func step() async {
        steps += 1
        let ui = app.ui, watch = app.watch, activity = app.activity, library = app.library
        let windowOpen = mainWindow?.isVisible == true
        let page = ui.page ?? .home
        typealias Action = (String, () async -> Void)

        // Always reachable: menu bar, app menu, global shortcut, time passing.
        var always: [Action] = [
            ("menuTeach", { self.app.teachSkill() }),
            ("menuOpen", { self.app.openWorkspace() }),
            ("settings", { await self.openAndCloseSettings() }),
            ("shortcut", { await self.pressShortcut() }),
            ("relaunch", { self.checkPersistence() }),
        ]
        if watch.isPlaying { always.append(("tick", { self.advance(self.rng.int(1...9)) })) }
        // The notch pill is always on screen on a notched Mac; elsewhere only while the strip is open.
        if app.notch.hasNotch || app.notch.isExpanded { always.append(("notchTap", { await self.tapNotch() })) }

        // What the main window offers on the current page. Nothing here while the window is closed.
        var onScreen: [Action] = []
        if windowOpen {
            onScreen.append(("nav", { ui.page = self.rng.pick(PrototypePage.allCases) }))
            onScreen.append(("toolbarTeach", { ui.showTeaching(watch: watch) }))
            onScreen.append(("closeMain", { self.mainWindow?.performClose(nil) }))
            switch page {
            case .home:
                onScreen.append(("homeTeach", { ui.showTeaching(watch: watch) }))
                onScreen.append(("exploreSample", { ui.page = .skills }))
            case .teach where ui.teachingStep == 0:
                onScreen.append(("editDescribe", {
                    ui.skillName = self.rng.pick(self.names); ui.clientName = self.rng.pick(self.clients)
                    if self.rng.chance(40) { ui.rules = self.rng.pick(self.notes) }
                }))
                // "Start Watch demo" / "Resume Watch demo" is disabled without a name and client.
                if ui.canSaveSkill { onScreen.append(("startWatch", { ui.startWatch(watch) })) }
            case .teach where ui.teachingStep == 1:
                // The Watch view: its buttons depend on the session's state.
                onScreen.append(("backToDescribe", { ui.teachingStep = 0 }))
                if watch.isPlaying { onScreen.append(("stopButton", { watch.stop() })) }
                if watch.isPresented {
                    onScreen.append(("addNote", { watch.ruleDraft = self.rng.pick(self.notes); watch.addRule() }))
                }
                if watch.isPresented && !watch.isPlaying {
                    onScreen.append(("replay", { watch.start(keepingRules: true) }))
                    onScreen.append(("review", { self.review() }))
                }
            case .teach:
                onScreen.append(("backToShow", { ui.teachingStep = 1 }))
                if ui.canSaveSkill { onScreen.append(("saveSkill", { await self.save() })) }
            case .skills:
                onScreen.append(("selectSkill", { ui.selectedSkill = self.rng.pick(library.skills) }))
                onScreen.append(("pickCase", { ui.scenario = self.rng.pick(SampleCase.allCases) }))
                // "Rehearse sample" is disabled while a rehearsal runs.
                if !activity.isRehearsing && library.canRehearse { onScreen.append(("rehearse", { await self.rehearse() })) }
            case .results:
                if !library.receipts.isEmpty {
                    onScreen.append(("export", { self.export() }))
                    onScreen.append(("tryAnotherCase", { ui.page = .skills }))
                } else {
                    onScreen.append(("exploreSample", { ui.page = .skills }))
                }
            case .account:
                break
            }
        }
        // The demo only runs when the app is launched with --notch-demo, from a resting state.
        if !watch.isPresented && activity.mode == .idle && rng.chance(15) { onScreen.append(("demo", { activity.playDemo() })) }

        // People mostly act on the screen in front of them (65%); otherwise anything reachable.
        let (name, action) = !onScreen.isEmpty && rng.chance(65) ? rng.pick(onScreen) : rng.pick(always + onScreen)
        trail.append(name)
        edges[name, default: 0] += 1
        await action()
        await pump(Double(rng.int(5...40)))
        checkInvariants()
        await checkNotchOpenness()
        recordNodes()
    }

    // MARK: Actions with their own expectations

    private func advance(_ seconds: Int) {
        options.clock.time += TimeInterval(seconds)
        app.watch.advance()
    }

    private func pressShortcut() async {
        let wasPlaying = app.watch.isPlaying
        let before = app.activity.mode
        app.shortcutPressed()
        await pump(30)
        if wasPlaying {
            expect(!app.watch.isPlaying && app.ui.page == .teach && app.ui.teachingStep == 2, "shortcut.stopsWatch",
                   "pressing the shortcut during Watch must stop it and open Review")
        } else if before == .idle || before == .demo {
            expect(app.watch.isPlaying, "shortcut.startsWatch", "pressing the shortcut when idle must start Watch")
        }
    }

    private func tapNotch() async {
        let expected = app.activity.page
        app.notch.tap()
        await pump(30)
        expect(mainWindow?.isVisible == true, "notch.tapOpensWindow", "clicking the notch must show the main window")
        if expected != .teach {
            expect(app.ui.page == expected, "notch.tapOpensPage", "clicking the notch must open \(expected.rawValue); got \(app.ui.page?.rawValue ?? "nil")")
        }
    }

    private func review() {
        let pending = app.watch.ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = app.watch.rules + (pending.isEmpty ? [] : [pending])
        app.ui.reviewWatch(app.watch)
        let lines = app.ui.rules.components(separatedBy: .newlines)
        for rule in taken where !lines.contains(rule) {
            fail("review.keepsNotes", "note \"\(rule)\" missing from Review")
        }
        let once = app.ui.rules
        app.ui.reviewWatch(app.watch)
        expect(app.ui.rules == once, "review.noDuplicates", "reviewing twice must not duplicate notes")
        expect(app.ui.teachingStep == 2 && !app.watch.isPlaying, "review.opensReview", "Review must stop Watch and show step 3")
    }

    private func save() async {
        let before = app.library.skills.count
        let name = app.ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        app.ui.saveReviewedSkill(library: app.library, watch: app.watch, activity: app.activity)
        await pump(20)
        expect(app.library.skills.count == before + 1, "save.addsOneSkill", "saving must add exactly one skill")
        expect(app.library.skills.last?.name == name, "save.trimsName", "the saved name must be the trimmed name")
        expect(app.ui.page == .skills && !app.watch.isPresented, "save.opensSkills", "saving must end Watch and open Skills")
        expect(app.activity.mode == .learned, "save.showsNewSkill", "the notch must show New skill after saving")
    }

    private func rehearse() async {
        let before = app.library.receipts.count
        let missing = app.ui.scenario == .missing
        app.ui.rehearseActiveSkill(library: app.library, activity: app.activity)
        visit("notch.rehearsing")
        expect(app.activity.mode == .rehearsing && app.activity.dot == .rehearse, "rehearse.showsReadOnly",
               "rehearsing must show the blue read-only strip")
        await waitUntil(3) { self.app.library.receipts.count > before || self.app.activity.mode != .rehearsing }
        expect(app.library.receipts.count == before + 1, "rehearse.addsOneReceipt", "a finished rehearsal must add exactly one receipt")
        guard let receipt = app.library.receipts.first else { return }
        expect(receipt.missingSpend == missing, "rehearse.caseMatches", "the receipt must match the chosen case")
        if missing {
            expect(receipt.report.contains("(DRAFT, incomplete)") && receipt.report.contains("[missing: needs input]"),
                   "rehearse.missingIsDraft", "a missing-spend report must be an incomplete draft that never estimates")
            expect(app.activity.detail == "Not ready to send", "rehearse.notchNotReady", "the notch must say Not ready to send")
        }
        expect(app.ui.page == .results && app.ui.selectedReceipt == receipt.id, "rehearse.opensReceipt",
               "a finished rehearsal must open its receipt")
    }

    private func export() {
        guard let receipt = app.library.receipts.first else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-export-\(UUID().uuidString).md")
        do {
            try app.library.write(receipt, to: url)
            visit("modal.export.write")
        } catch {
            fail("export.readsBack", "export write/read-back failed: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func openAndCloseSettings() async {
        app.openSettings()
        await pump(20)
        let window = NSApp.windows.first { $0.title == "Understudy Settings" }
        expect(window?.isVisible == true, "settings.opens", "the shortcut settings window must open")
        visit("window.settings")
        window?.performClose(nil)
        await pump(10)
    }

    private func checkPersistence() {
        let reloaded = SkillLibrary(auth: AppModel(config: nil), file: options.libraryFile)
        expect(reloaded.skills.map(\.id) == app.library.skills.map(\.id), "persist.skills", "skills must survive a relaunch")
        expect(reloaded.receipts.map(\.id) == app.library.receipts.map(\.id), "persist.receipts", "receipts must survive a relaunch")
    }

    // MARK: Rules checked after every step

    private func checkInvariants() {
        let ui = app.ui, activity = app.activity
        expect(ui.page != nil && (0...2).contains(ui.teachingStep), "state.valid", "page must be set and Teach step within 1–3")
        expect(app.library.mode == .sample && app.model.client == nil, "sample.noServer", "a Mac without a server stays in Sample mode")
        expect(!app.library.skills.isEmpty, "skills.nonEmpty", "there is always at least one skill")
        expect(activity.rows.count <= 4, "notch.rowCap", "the notch shows at most 4 rows")
        if activity.mode != .idle {
            expect(activity.footer.contains("Simulated") || activity.footer.contains("Concept demonstration"),
                   "notch.honestLabel", "every notch state must say Simulated or Concept demonstration")
        }

        if app.watch.isPlaying && activity.mode != .demo && ![NotchActivity.Mode.learned, .rehearsing, .receipt].contains(activity.mode) {
            expect(activity.mode == .watching && activity.dot == .pulse, "notch.watching", "a playing Watch must show the pulsing Watching strip")
        }
    }

    /// The notch reacts to a state change on the next pass of the run loop, so a mismatch gets up
    /// to 100 ms to settle (well under what a person notices) before it counts as a failure.
    private func checkNotchOpenness() async {
        let active: [NotchActivity.Mode] = [.watching, .learned, .rehearsing, .receipt, .demo]
        func mismatch(_ mode: NotchActivity.Mode) -> Bool {
            (mode == .idle && app.notch.isExpanded) || (active.contains(mode) && !app.notch.isExpanded)
        }
        let mode = app.activity.mode
        guard mismatch(mode) else { return }
        await pump(100)
        guard app.activity.mode == mode, mismatch(mode) else { return }
        fail(mode == .idle ? "notch.idleCollapsed" : "notch.activeExpanded",
             mode == .idle ? "an idle notch must be collapsed" : "an active notch must be open (\(mode))")
    }

    private func recordNodes() {
        visit("page.\(app.ui.page?.rawValue ?? "none")")
        if app.ui.page == .teach { visit("teach.step\(app.ui.teachingStep + 1)") }
        visit("notch.\(app.activity.mode)")
        visit(mainWindow?.isVisible == true ? "window.main.open" : "window.main.closed")
        visit("account.\(app.model.phase == .notConfigured ? "notConfigured" : "other")")
    }

    // MARK: Helpers

    private func visit(_ node: String) { nodes[node, default: 0] += 1 }

    private func expect(_ condition: Bool, _ rule: String, _ detail: String) {
        if !condition { fail(rule, detail) }
    }

    private func fail(_ rule: String, _ detail: String) {
        // One entry per rule, with the steps that led there, so it can be reproduced.
        guard !failures.contains(where: { ($0["rule"] as? String) == rule }) else { return }
        failures.append(["rule": rule, "detail": detail, "seed": options.seed, "session": session,
                         "step": steps, "trail": Array(trail.suffix(15))])
        print("FAIL \(rule): \(detail) [seed \(options.seed), session \(session), trail \(trail.suffix(8).joined(separator: " → "))]")
    }

    private func pump(_ milliseconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(milliseconds * 1_000_000))
    }

    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { await pump(5) }
    }
}
