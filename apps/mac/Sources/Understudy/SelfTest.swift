import AppKit
import UnderstudyCore

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
    let libraryFile: LocalStore
    /// Where Watch saves recordings: a temporary folder, never the person's.
    let recordings: URL
    let clock = TestClock()

    init?(arguments: [String]) {
        guard let flag = arguments.first(where: { $0 == "--self-test" || $0.hasPrefix("--self-test=") }) else { return nil }
        let parts = flag.split(separator: "=", maxSplits: 1).dropFirst().first?.split(separator: ",") ?? []
        sessions = parts.first.flatMap { Int($0) } ?? 200
        seed = parts.dropFirst().first.flatMap { UInt64($0) } ?? 1
        let outArg = arguments.first(where: { $0.hasPrefix("--self-test-out=") })?.dropFirst("--self-test-out=".count)
        out = URL(fileURLWithPath: outArg.map(String.init) ?? NSTemporaryDirectory() + "understudy-self-test")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-self-test-\(UUID().uuidString)")
        libraryFile = LocalStore(url: dir.appendingPathComponent("library.json"))
        recordings = dir.appendingPathComponent("recordings")
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
    /// Steps the simulated person approved while a run waited for them (by skill step id).
    private var approved: Set<String> = []
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
            app.env.ui.page = page
            await pump(250)
            snapshot(mainWindow, name: "page-\(page.rawValue)")
        }
        app.env.ui.page = .teach
        app.env.ui.teachingStep = 0
        await pump(250)
        snapshot(mainWindow, name: "teach-1-describe")
        app.env.ui.startWatch(app.env.watch)
        for _ in 0..<4 { advance(3) }
        await pump(settle)
        snapshot(mainWindow, name: "teach-2-show")
        snapshot(notchWindow, name: "notch-watching")
        app.env.watch.stop()
        await pump(settle)
        snapshot(notchWindow, name: "notch-stopped")
        app.env.ui.reviewWatch(app.env.watch)
        await pump(250)
        snapshot(mainWindow, name: "teach-3-review")
        app.env.ui.saveReviewedSkill(library: app.env.library, watch: app.env.watch, activity: app.env.activity)
        await pump(settle)
        snapshot(notchWindow, name: "notch-learned")
        await waitUntil(6) { self.app.env.activity.mode == .idle }
        // The sample rehearsal is offered for skills without recorded steps, like the sample.
        app.env.ui.selectedSkill = app.env.library.skills.first { $0.isSample }
        app.env.ui.scenario = .missing
        app.env.ui.rehearseActiveSkill(library: app.env.library, activity: app.env.activity)
        await pump(settle)
        snapshot(notchWindow, name: "notch-rehearsing")
        await waitUntil(8) { self.app.env.activity.mode == .receipt }
        await pump(settle)
        snapshot(notchWindow, name: "notch-receipt")
        await pump(200)
        snapshot(mainWindow, name: "page-Receipts-after-rehearsal")
        app.env.activity.dismiss()
        app.env.activity.playDemo()
        await pump(3_500)
        snapshot(notchWindow, name: "notch-demo")
        app.env.activity.dismiss()
        await pump(settle * 2)
        snapshot(notchWindow, name: "notch-idle")
        app.openSettings()
        await pump(250)
        checkSettingsWindow()
        NSApp.windows.first { $0.title == "Understudy Settings" }?.performClose(nil)
        app.env.ui.page = .home
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
            // The captures reach every notch state on purpose, so they count toward coverage;
            // otherwise a short run could miss a state by chance (the demo is rare in random walks).
            visit("notch.\(app.env.activity.mode)")
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
        let ui = app.env.ui, watch = app.env.watch, activity = app.env.activity, library = app.env.library
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
        if watch.isWatching {
            always.append(("tick", { self.advance(self.rng.int(1...9)) }))
            // Sharing can be stopped from macOS's menu bar; Watch must stop and save.
            always.append(("stopSharing", {
                self.script.endSharing()
                self.expect(self.app.env.watch.phase == .stopped && self.app.env.watch.recording != nil,
                            "watch.stopsWhenSharingEnds", "when sharing ends, Watch must stop and save the take")
            }))
        }
        // Videos finish writing a moment after Stop, sometimes after another take has started.
        if rng.chance(50) { script.finishVideos() }
        // A skill's trigger fires: its time comes, its app opens, or a file lands in its folder.
        let scheduler = app.env.scheduler
        if let skill = scheduler.scheduled.first(where: { _ in rng.chance(50) }) ?? scheduler.scheduled.first, rng.chance(30) {
            always.append(("triggerFires", { await self.triggerFires(skill) }))
        }
        // Accessibility access can be turned off in System Settings at any time (rarely), and a
        // person who sees Watch blocked usually turns it back on.
        if script.failure == nil ? rng.chance(3) : rng.chance(40) {
            always.append(("permission", { self.script.failure = self.script.failure == nil ? ScreenCapture.accessibilityNeeded : nil }))
        }
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
                // Shown when Watch couldn't start (e.g. no Accessibility access), with the reason.
                if !watch.isPresented && watch.phase != .starting { onScreen.append(("startWatchHere", { watch.start() })) }
                if watch.isWatching { onScreen.append(("stopButton", { watch.stop() })) }
                if watch.isPresented {
                    onScreen.append(("addNote", { watch.ruleDraft = self.rng.pick(self.notes); watch.addRule() }))
                }
                if watch.isPresented && !watch.isWatching {
                    onScreen.append(("recordAgain", { watch.start(keepingRules: true) }))
                    onScreen.append(("review", { self.review() }))
                }
            case .teach:
                onScreen.append(("backToShow", { ui.teachingStep = 1 }))
                if ui.canSaveSkill { onScreen.append(("saveSkill", { await self.save() })) }
                // Each reviewed step has Move up, Delete, and (for typing) a text field.
                if !ui.draftSteps.isEmpty { onScreen.append(("editStep", { self.editStep() })) }
            case .skills:
                let active = ui.activeSkill(in: library)
                let runner = app.env.runner
                onScreen.append(("selectSkill", { ui.selectedSkill = self.rng.pick(library.skills) }))
                if !active.definition.steps.isEmpty {
                    // The run panel: Run now, Test step by step, then Stop, Approve, and Skip while it runs.
                    if !runner.isRunning {
                        onScreen.append(("runNow", { await self.run(active, mode: .run) }))
                        onScreen.append(("runStepByStep", { await self.run(active, mode: .stepByStep) }))
                    } else if runner.skill?.id == active.id {
                        onScreen.append(("stopRun", { await self.stopRun() }))
                        if runner.pause != nil {
                            onScreen.append(("approveStep", { await self.approveStep() }))
                            onScreen.append(("skipStep", { runner.skip() }))
                        }
                    }
                    // When it runs: pick a kind, fill it in, save.
                    onScreen.append(("editTrigger", { await self.editTrigger(active) }))
                    if !runner.isRunning && runner.skill?.id == active.id && !runner.results.isEmpty {
                        onScreen.append(("seeRunReceipt", { ui.selectedReceipt = runner.lastReceipt; ui.page = .results }))
                    }
                }
                if active.definition.steps.isEmpty {
                    // The sample rehearsal shows only for skills without recorded steps.
                    onScreen.append(("pickCase", { ui.scenario = self.rng.pick(SampleCase.allCases) }))
                    // "Rehearse sample" is disabled while a rehearsal runs.
                    if !activity.isRehearsing && library.canRehearse && !app.env.runner.isRunning {
                        onScreen.append(("rehearse", { await self.rehearse() }))
                    }
                    if !active.isSample && watch.latestRecording() != nil {
                        onScreen.append(("createSteps", { await self.createSteps(for: active) }))
                    }
                }
            case .results:
                let shown = library.receipts.first { $0.id == ui.selectedReceipt } ?? library.receipts.first
                if shown?.isRun == true {
                    onScreen.append(("backToSkills", { ui.page = .skills }))
                } else if shown != nil {
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

    /// The scripted capture that stands in for the screen during the self-test. It reports a
    /// video for each take, finished later, as the recorder does.
    private var script: ScriptedCapture {
        let script = app.env.capture as! ScriptedCapture
        // Now and then the video can't be saved (e.g. the disk is full); Watch must say so.
        script.video = rng.chance(5) ? ScriptedCapture.failingVideo : "screen.mov"
        return script
    }

    /// Time passes during Watch, and the person does the next step of the task.
    private func advance(_ seconds: Int) {
        options.clock.time += TimeInterval(seconds)
        app.env.watch.advance()
        script.emitNext()
    }

    private func pressShortcut() async {
        let wasWatching = app.env.watch.isWatching
        let before = app.env.activity.mode
        app.shortcutPressed()
        await pump(30)
        if wasWatching {
            expect(!app.env.watch.isWatching && app.env.ui.page == .teach && app.env.ui.teachingStep == 2, "shortcut.stopsWatch",
                   "pressing the shortcut during Watch must stop it and open Review")
        } else if before == .idle || before == .demo {
            expect(app.env.watch.isWatching || app.env.watch.problem != nil, "shortcut.startsWatch",
                   "pressing the shortcut when idle must start Watch, or say why it can't")
        }
    }

    private func tapNotch() async {
        let expected = app.env.activity.page
        if app.env.activity.mode == .scheduled, let counting = app.env.scheduler.pending {
            // During the countdown before a triggered run, a click cancels it. (Another queued
            // skill may start its own countdown next.)
            app.notch.tap()
            await pump(10)
            expect(app.env.scheduler.pending?.id != counting.id && !(app.env.runner.isRunning && app.env.runner.skill?.id == counting.id),
                   "trigger.clickCancels", "clicking the notch during the countdown cancels that run")
            return
        }
        app.notch.tap()
        await pump(30)
        expect(mainWindow?.isVisible == true, "notch.tapOpensWindow", "clicking the notch must show the main window")
        if expected != .teach {
            expect(app.env.ui.page == expected, "notch.tapOpensPage", "clicking the notch must open \(expected.rawValue); got \(app.env.ui.page?.rawValue ?? "nil")")
        }
    }

    private func review() {
        let pending = app.env.watch.ruleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = app.env.watch.rules + (pending.isEmpty ? [] : [pending])
        app.env.ui.reviewWatch(app.env.watch)
        let lines = app.env.ui.rules.components(separatedBy: .newlines)
        for rule in taken where !lines.contains(rule) {
            fail("review.keepsNotes", "note \"\(rule)\" missing from Review")
        }
        let once = app.env.ui.rules
        app.env.ui.reviewWatch(app.env.watch)
        expect(app.env.ui.rules == once, "review.noDuplicates", "reviewing twice must not duplicate notes")
        expect(app.env.ui.teachingStep == 2 && !app.env.watch.isWatching, "review.opensReview", "Review must stop Watch and show step 3")
    }

    private func save() async {
        let before = app.env.library.skills.count
        let name = app.env.ui.skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = app.env.ui.draftSteps
        app.env.ui.saveReviewedSkill(library: app.env.library, watch: app.env.watch, activity: app.env.activity)
        await pump(20)
        expect(app.env.library.skills.count == before + 1, "save.addsOneSkill", "saving must add exactly one skill")
        expect(app.env.library.skills.last?.name == name, "save.trimsName", "the saved name must be the trimmed name")
        expect(app.env.library.skills.last?.definition.steps == steps && app.env.ui.draftSteps.isEmpty, "save.keepsReviewedSteps",
               "the saved skill must have exactly the reviewed steps")
        expect(app.env.ui.page == .skills && !app.env.watch.isPresented, "save.opensSkills", "saving must end Watch and open Skills")
        // A triggered run's countdown or a run in progress takes precedence over the message.
        expect(app.env.activity.mode == .learned || app.env.scheduler.pending != nil || app.env.runner.isRunning,
               "save.showsNewSkill", "the notch must show New skill after saving")
    }

    /// Delete, move up, or retype one reviewed step.
    private func editStep() {
        let ui = app.env.ui
        let before = ui.draftSteps
        let index = rng.int(0...(before.count - 1))
        switch rng.int(0...2) {
        case 0:
            ui.deleteStep(at: index)
            expect(ui.draftSteps.count == before.count - 1 && !ui.draftSteps.contains { $0.id == before[index].id },
                   "steps.delete", "Delete removes exactly that step")
        case 1:
            ui.moveStepUp(at: index)
            expect(Set(ui.draftSteps.map(\.id)) == Set(before.map(\.id)) && (index == 0 || ui.draftSteps[index - 1].id == before[index].id),
                   "steps.moveUp", "Move up swaps a step with the one above and loses nothing")
        default:
            let text = rng.pick(notes)
            ui.setTypedText(text, at: index)
            if before[index].parameters["action"] == "type" {
                expect(ui.draftSteps[index].parameters["text"] == text, "steps.retype", "editing a Type step changes what it types")
            } else {
                expect(ui.draftSteps == before, "steps.retypeOnlyTyping", "only Type steps have text to edit")
            }
        }
    }

    /// Choose when a skill runs, as the editor allows, and save it.
    private func editTrigger(_ skill: Skill) async {
        let ui = app.env.ui, scheduler = app.env.scheduler
        ui.editTrigger(of: skill)
        let kind = rng.pick(SkillDefinition.Trigger.Kind.allCases)
        ui.triggerDraft.kind = kind
        switch kind {
        case .schedule:
            ui.triggerDraft.hour = rng.int(0...23); ui.triggerDraft.minute = rng.int(0...59)
            for _ in 0..<rng.int(0...3) { ui.toggleWeekday(rng.int(1...7)) }
        case .interval: ui.triggerDraft.everyHours = rng.int(1...24)
        case .appOpened: ui.triggerDraft.app = "com.apple.TextEdit"; ui.triggerDraft.appName = "TextEdit"
        case .fileAdded: ui.triggerDraft.folder = options.recordings.path
        case .manual: break
        }
        let trigger = ui.finishedTrigger(device: scheduler.device)
        guard trigger.isComplete else { return }   // Save is disabled until it is
        ui.saveTrigger(trigger, of: skill, library: app.env.library)
        await pump(20)
        let saved = app.env.library.skills.first { $0.id == skill.id }?.definition.trigger
        expect(saved == trigger && (kind == .manual || saved?.device == scheduler.device), "trigger.saved",
               "a saved trigger is exactly what was chosen, set on this Mac")
        if kind == .schedule || kind == .interval {
            expect(scheduler.nextRun(of: app.env.library.skills.first { $0.id == skill.id } ?? skill) != nil, "trigger.nextRun",
                   "a schedule or interval always has a next run")
        }
    }

    /// A trigger fires. The run waits its turn, counts down in the notch, then runs.
    private func triggerFires(_ skill: Skill) async {
        let scheduler = app.env.scheduler, runner = app.env.runner
        let wasRunning = runner.isRunning
        let watching = app.env.watch.isWatching
        scheduler.fire(skill)
        await pump(5)
        if watching {
            // It waits while Watch records: no countdown over the recording.
            expect(app.env.activity.mode != .scheduled && !(runner.isRunning && runner.skill?.id == skill.id), "trigger.waitsForWatch",
                   "a triggered run waits while Watch records")
        } else if !wasRunning && scheduler.pending?.id == skill.id {
            await waitUntil(0.5) { self.app.env.activity.mode == .scheduled || runner.isRunning || scheduler.pending == nil }
            expect(app.env.activity.mode == .scheduled || runner.isRunning || scheduler.pending == nil, "trigger.countdownFirst",
                   "a triggered run counts down in the notch before it starts")
        }
    }

    /// Run now / Test step by step. A step can fail now and then, as when a control isn't found.
    private func run(_ skill: Skill, mode: RunEngine.Mode) async {
        let runner = app.env.runner, library = app.env.library
        let before = library.receipts.count
        approved = []
        if rng.chance(15) { performer.failNext = "Couldn't find the control." }
        let watching = app.env.watch.isWatching
        let started = runner.start(skill, mode: mode)
        if watching {
            expect(!started && runner.problem != nil, "run.notDuringWatch", "a run never starts while Watch records")
            return
        }
        expect(started && runner.skill?.id == skill.id, "run.starts", "Run starts a skill that has steps")
        await pump(30)
        checkRunEnded(before: before)
    }

    private func approveStep() async {
        let runner = app.env.runner
        if let index = runner.current { approved.insert(runner.steps[index].id) }
        let before = app.env.library.receipts.count
        runner.approve()
        await pump(30)
        checkRunEnded(before: before)
    }

    private func stopRun() async {
        let before = app.env.library.receipts.count
        app.env.runner.stop()
        await pump(10)
        expect(!app.env.runner.isRunning && app.env.library.receipts.count == before + 1 && app.env.library.receipts.first?.outcome == "Stopped",
               "run.stopSavesReceipt", "Stop ends the run and saves a receipt that says it was stopped")
    }

    /// A run that ended has exactly one new receipt, from a real run, with one line per step.
    private func checkRunEnded(before: Int) {
        let runner = app.env.runner
        guard !runner.isRunning else { return }
        let receipt = app.env.library.receipts.first
        expect(app.env.library.receipts.count == before + 1 && receipt?.isRun == true && receipt?.steps.count == runner.steps.count,
               "run.oneReceipt", "every finished run saves exactly one receipt with a line per step")
    }

    private var performer: ScriptedPerformer { app.env.performer as! ScriptedPerformer }

    private func createSteps(for skill: Skill) async {
        app.env.ui.addStepsFromLatestRecording(to: skill, library: app.env.library, watch: app.env.watch)
        await pump(20)
        let updated = app.env.library.skills.first { $0.id == skill.id }
        expect(updated?.definition.steps.isEmpty == false && updated?.definition.recording != nil, "steps.fromLatestRecording",
               "a skill without steps gets steps from the latest recording")
    }

    private func rehearse() async {
        let before = app.env.library.receipts.count
        let missing = app.env.ui.scenario == .missing
        app.env.ui.rehearseActiveSkill(library: app.env.library, activity: app.env.activity)
        visit("notch.rehearsing")
        expect(app.env.activity.mode == .rehearsing && app.env.activity.dot == .rehearse, "rehearse.showsReadOnly",
               "rehearsing must show the blue read-only strip")
        await waitUntil(3) { self.app.env.library.receipts.count > before || self.app.env.activity.mode != .rehearsing }
        expect(app.env.library.receipts.count == before + 1, "rehearse.addsOneReceipt", "a finished rehearsal must add exactly one receipt")
        guard let receipt = app.env.library.receipts.first else { return }
        expect(receipt.missingSpend == missing, "rehearse.caseMatches", "the receipt must match the chosen case")
        if missing {
            expect(receipt.report.contains("(DRAFT, incomplete)") && receipt.report.contains("[missing: needs input]"),
                   "rehearse.missingIsDraft", "a missing-spend report must be an incomplete draft that never estimates")
            expect(app.env.activity.detail == "Not ready to send", "rehearse.notchNotReady", "the notch must say Not ready to send")
        }
        expect(app.env.ui.page == .results && app.env.ui.selectedReceipt == receipt.id, "rehearse.opensReceipt",
               "a finished rehearsal must open its receipt")
    }

    private func export() {
        guard let receipt = app.env.library.receipts.first else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-export-\(UUID().uuidString).md")
        do {
            try app.env.library.write(receipt, to: url)
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
        expect(reloaded.skills.map(\.id) == app.env.library.skills.map(\.id), "persist.skills", "skills must survive a relaunch")
        expect(reloaded.receipts.map(\.id) == app.env.library.receipts.map(\.id), "persist.receipts", "receipts must survive a relaunch")
    }

    // MARK: Rules checked after every step

    private func checkInvariants() {
        let ui = app.env.ui, activity = app.env.activity
        expect(ui.page != nil && (0...2).contains(ui.teachingStep), "state.valid", "page must be set and Teach step within 1–3")
        expect(app.env.library.mode == .sample && app.env.model.client == nil, "sample.noServer", "a Mac without a server stays in Sample mode")
        expect(!app.env.library.skills.isEmpty, "skills.nonEmpty", "there is always at least one skill")
        expect(activity.rows.count <= 4, "notch.rowCap", "the notch shows at most 4 rows")
        switch activity.mode {
        case .idle: break
        case .watching, .stopped:
            expect(activity.footer == NotchActivity.watchFooter, "notch.honestLabel", "Watch must say it records on this Mac, never passwords")
        case .learned where activity.footer == NotchActivity.learnedFooter:
            break   // a skill whose steps came from a recording
        case .running:
            expect(activity.footer == NotchActivity.runFooter, "notch.honestLabel", "a real run says it runs on this Mac")
        case .scheduled:
            expect(activity.footer == NotchActivity.countdownFooter, "notch.honestLabel", "the countdown says a click cancels it")
            expect(!app.env.runner.isRunning, "trigger.countdownBeforeRun", "no run happens during a countdown")
        case .receipt where activity.footer == NotchActivity.runReceiptFooter:
            break   // the receipt of a real run
        default:
            expect(activity.footer.contains("Simulated") || activity.footer.contains("Concept demonstration"),
                   "notch.honestLabel", "every simulated notch state must say Simulated or Concept demonstration")
        }
        let runner = app.env.runner
        expect(!(runner.isRunning && app.env.watch.isWatching), "run.notDuringWatch", "a run and Watch never overlap")
        for (index, step) in runner.steps.enumerated() where step.effect.needsApproval && runner.results[index].status == .done {
            expect(approved.contains(step.id), "run.approvalRequired", "a step that sends or deletes never runs without approval")
        }
        let watch = app.env.watch
        expect(watch.problem == nil || !watch.isWatching, "watch.problemMeansNotWatching", "Watch shows a problem only when it isn't recording")
        expect(!watch.isPresented || watch.actions.count <= ScriptedCapture.script.count, "watch.actionsInOrder",
               "Watch records each action once")
        if watch.phase == .stopped {
            expect(watch.recording?.actions == watch.actions && watch.recording?.notes == watch.rules, "watch.savedOnStop",
                   "a stopped Watch has saved its actions and notes")
        }

        if app.env.watch.isWatching && activity.mode != .demo && ![NotchActivity.Mode.learned, .rehearsing, .receipt].contains(activity.mode) {
            expect(activity.mode == .watching && activity.dot == .pulse, "notch.watching", "a playing Watch must show the pulsing Watching strip")
        }
    }

    /// The notch reacts to a state change on the next pass of the run loop, so a mismatch gets up
    /// to 100 ms to settle (well under what a person notices) before it counts as a failure.
    private func checkNotchOpenness() async {
        let active: [NotchActivity.Mode] = [.watching, .learned, .rehearsing, .scheduled, .running, .receipt, .demo]
        func mismatch(_ mode: NotchActivity.Mode) -> Bool {
            (mode == .idle && app.notch.isExpanded) || (active.contains(mode) && !app.notch.isExpanded)
        }
        let mode = app.env.activity.mode
        guard mismatch(mode) else { return }
        await pump(100)
        guard app.env.activity.mode == mode, mismatch(mode) else { return }
        fail(mode == .idle ? "notch.idleCollapsed" : "notch.activeExpanded",
             mode == .idle ? "an idle notch must be collapsed" : "an active notch must be open (\(mode))")
    }

    private func recordNodes() {
        visit("page.\(app.env.ui.page?.rawValue ?? "none")")
        if app.env.ui.page == .teach { visit("teach.step\(app.env.ui.teachingStep + 1)") }
        visit("notch.\(app.env.activity.mode)")
        if app.env.watch.problem != nil { visit("watch.blocked") }
        let runner = app.env.runner
        if runner.isRunning { visit(runner.pause == nil ? "run.running" : "run.waiting") }
        if app.env.activity.mode == .scheduled { visit("trigger.countdown") }
        if !app.env.scheduler.scheduled.isEmpty { visit("trigger.set") }
        if app.env.ui.page == .results, (app.env.library.receipts.first { $0.id == app.env.ui.selectedReceipt } ?? app.env.library.receipts.first)?.isRun == true {
            visit("run.receipt")
        }
        visit(mainWindow?.isVisible == true ? "window.main.open" : "window.main.closed")
        visit("account.\(app.env.model.phase == .notConfigured ? "notConfigured" : "other")")
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
