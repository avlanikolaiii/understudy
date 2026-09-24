import AppKit
import Combine
import UnderstudyCore

/// Starts skills when their trigger fires: at a scheduled time, every N hours, when an app opens,
/// or when a file lands in a folder. Only triggers set on this Mac run here. A scheduled run the
/// Mac slept through runs when it wakes, if it's less than 2 hours late, once.
///
/// Before a triggered run, the notch counts down for 10 seconds; clicking it cancels. If the
/// person is using the Mac, the run waits (up to 10 minutes) until they pause, because a run
/// types and brings apps to the front. One run at a time: others wait their turn.
@MainActor
final class Scheduler: ObservableObject {
    /// The skill about to run, during the countdown.
    @Published private(set) var pending: Skill?

    static let countdown = 10.0
    static let catchUpWindow: TimeInterval = 2 * 3600
    static let idleNeeded: TimeInterval = 60
    static let idleWaitLimit: TimeInterval = 10 * 60

    let device: String
    private let library: SkillLibrary
    private let runner: RunController
    private let activity: NotchActivity
    private let now: () -> Date
    private let sleep: (Double) async -> Void
    private let idleSeconds: () -> TimeInterval
    /// True while a triggered run must wait, e.g. while Watch records (the run would type into it).
    private let busy: () -> Bool
    private let defaults: UserDefaults
    private var timers: [UUID: Timer] = [:]
    private var folders: [UUID: FolderWatch] = [:]
    private var observers: [NSObjectProtocol] = []
    /// Skills waiting their turn, with the values their trigger gave (e.g. the file that arrived).
    private var queue: [(skill: Skill, values: [String: String])] = []
    private var countdownTask: Task<Void, Never>?
    private var librarySink: AnyCancellable?

    init(library: SkillLibrary, runner: RunController, activity: NotchActivity, busy: @escaping () -> Bool,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
         idleSeconds: @escaping () -> TimeInterval = {
             CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
         }) {
        self.library = library; self.runner = runner; self.activity = activity; self.defaults = defaults
        self.now = now; self.sleep = sleep; self.idleSeconds = idleSeconds; self.busy = busy
        if let saved = defaults.string(forKey: "deviceID") { device = saved } else {
            device = UUID().uuidString
            defaults.set(device, forKey: "deviceID")
        }
    }

    /// Starts watching the library's triggers and the system's events.
    func start() {
        librarySink = library.$skills.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self.appOpened(app?.bundleIdentifier) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.refresh() }
        })
    }

    /// Skills whose trigger runs on this Mac.
    var scheduled: [Skill] {
        library.skills.filter { !$0.definition.steps.isEmpty && $0.definition.trigger.kind != .manual
            && $0.definition.trigger.isComplete && $0.definition.trigger.device == device }
    }

    func nextRun(of skill: Skill) -> Date? {
        let trigger = skill.definition.trigger
        guard trigger.device == device else { return nil }
        return trigger.nextRun(after: trigger.kind == .interval ? lastRun(skill) ?? now() : now())
    }

    /// Rebuilds timers and folder watches from the library, and runs a schedule missed while asleep.
    func refresh() {
        timers.values.forEach { $0.invalidate() }
        timers = [:]
        let skills = scheduled
        for id in folders.keys where !skills.contains(where: { $0.id == id && $0.definition.trigger.kind == .fileAdded }) {
            folders[id] = nil
        }
        for skill in skills {
            let trigger = skill.definition.trigger
            switch trigger.kind {
            case .schedule:
                if let due = trigger.lastScheduledRun(atOrBefore: now()), now().timeIntervalSince(due) < Self.catchUpWindow,
                   (lastRun(skill) ?? .distantPast) < due {
                    fire(skill)
                }
                arm(skill)
            case .interval:
                arm(skill)
            case .fileAdded:
                if folders[skill.id]?.path != trigger.folder, let path = trigger.folder {
                    folders[skill.id] = FolderWatch(path: path) { [weak self] file in
                        self?.fire(skill, values: ["file": (path as NSString).appendingPathComponent(file), "fileName": file])
                    }
                }
            case .appOpened, .manual:
                break
            }
        }
    }

    /// Cancels the countdown in the notch; the run doesn't happen this time.
    func cancelPending() {
        countdownTask?.cancel()
        countdownTask = nil
        if let skill = pending { markRun(skill) }
        pending = nil
        activity.hideCountdown()
        startNext()
    }

    /// A trigger fired: queue the skill, and start it when nothing else is running.
    func fire(_ skill: Skill, values: [String: String] = [:]) {
        guard !queue.contains(where: { $0.skill.id == skill.id }), pending?.id != skill.id,
              runner.skill?.id != skill.id || !runner.isRunning else { return }
        queue.append((skill, values))
        startNext()
    }

    // MARK: Private

    private func arm(_ skill: Skill) {
        guard let next = nextRun(of: skill) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.fire(skill)
                self.arm(skill)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[skill.id] = timer
    }

    private func appOpened(_ bundle: String?) {
        guard let bundle else { return }
        for skill in scheduled where skill.definition.trigger.kind == .appOpened && skill.definition.trigger.app == bundle {
            fire(skill)
        }
    }

    private func startNext() {
        guard pending == nil, !runner.isRunning, !queue.isEmpty else { return }
        let (skill, values) = queue.removeFirst()
        pending = skill
        countdownTask = Task { [weak self] in
            guard let self else { return }
            // Wait while Watch records, then for the person to pause, so the run doesn't type into
            // a recording or into what they're doing.
            while self.busy() {
                await self.sleep(15)
                if Task.isCancelled { return }
            }
            var waited: TimeInterval = 0
            while self.idleSeconds() < Self.idleNeeded && waited < Self.idleWaitLimit {
                await self.sleep(15); waited += 15
                if Task.isCancelled { return }
            }
            for remaining in stride(from: Int(Self.countdown), to: 0, by: -1) {
                // A run started by hand, or Watch started, meanwhile: this one waits its turn again.
                if self.runner.isRunning || self.busy() {
                    self.pending = nil
                    self.countdownTask = nil
                    self.queue.insert((skill, values), at: 0)
                    self.activity.hideCountdown()
                    return self.waitForRunThenNext()
                }
                self.activity.showCountdown(skill.name, seconds: remaining)
                await self.sleep(1)
                if Task.isCancelled { return }
            }
            self.pending = nil
            self.countdownTask = nil
            self.markRun(skill)
            if !self.runner.start(skill, mode: .run, values: values) {
                // E.g. Watch is recording, or Accessibility is off: say so instead of failing silently.
                self.activity.showRunProblem(skill.name, reason: self.runner.problem ?? "It couldn't start.")
            }
            self.waitForRunThenNext()
        }
    }

    private func waitForRunThenNext() {
        Task { [weak self] in
            while let self, self.runner.isRunning || self.busy() { await self.sleep(1) }
            self?.startNext()
        }
    }

    private func lastRun(_ skill: Skill) -> Date? { defaults.object(forKey: "lastRun.\(skill.id)") as? Date }
    private func markRun(_ skill: Skill) { defaults.set(now(), forKey: "lastRun.\(skill.id)") }
}

/// Watches a folder and calls `added` with the name of each new visible file in it.
@MainActor
final class FolderWatch {
    let path: String
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String>
    private let added: (String) -> Void

    init(path: String, added: @escaping (String) -> Void) {
        self.path = path
        self.added = added
        known = Self.files(in: path)
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // Files are often written in several steps; look once things settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { self?.check() } }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }

    func check() {
        let now = Self.files(in: path)
        let new = now.subtracting(known)
        known = now
        new.sorted().forEach(added)
    }

    static func files(in path: String) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") })
    }
}
