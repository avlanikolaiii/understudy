import Foundation

extension SkillDefinition {
    /// When a skill runs, set by the person in the app. Schedules and events run on the Mac where
    /// they were set (`device`), while it's awake and Understudy is open.
    public struct Trigger: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case manual, schedule, interval, appOpened, fileAdded
        }

        public var kind: Kind
        /// In plain words, e.g. "Weekdays at 9:00". Kept for readers of the stored skill.
        public var detail: String
        /// `schedule`: the time of day.
        public var hour: Int?
        public var minute: Int?
        /// `schedule`: the days it runs, 1 = Sunday … 7 = Saturday. Empty or nil means every day.
        public var weekdays: [Int]?
        /// `interval`: hours between runs.
        public var everyHours: Int?
        /// `appOpened`: the app's bundle identifier and name.
        public var app: String?
        public var appName: String?
        /// `fileAdded`: the folder watched.
        public var folder: String?
        /// The Mac that runs it, so a skill in an account used on two Macs runs once.
        public var device: String?

        public init(kind: Kind, detail: String = "", hour: Int? = nil, minute: Int? = nil, weekdays: [Int]? = nil,
                    everyHours: Int? = nil, app: String? = nil, appName: String? = nil, folder: String? = nil, device: String? = nil) {
            self.kind = kind; self.hour = hour; self.minute = minute; self.weekdays = weekdays; self.everyHours = everyHours
            self.app = app; self.appName = appName; self.folder = folder; self.device = device
            self.detail = detail
            if detail.isEmpty { self.detail = summary }
        }

        public static let manual = Trigger(kind: .manual, detail: "When you start it")

        public static let weekdays = [2, 3, 4, 5, 6]

        /// What the trigger does, in a few words.
        public var summary: String {
            switch kind {
            case .manual:
                return "When you start it"
            case .schedule:
                let time = String(format: "%d:%02d", hour ?? 9, minute ?? 0)
                let days = Set(weekdays ?? [])
                if days.isEmpty || days.count == 7 { return "Every day at \(time)" }
                if days == Set(Self.weekdays) { return "Weekdays at \(time)" }
                let names = Calendar(identifier: .gregorian).shortWeekdaySymbols
                return days.sorted().map { names[$0 - 1] }.joined(separator: ", ") + " at \(time)"
            case .interval:
                let hours = everyHours ?? 1
                return hours == 1 ? "Every hour" : "Every \(hours) hours"
            case .appOpened:
                return "When \(appName ?? app ?? "an app") opens"
            case .fileAdded:
                return "When a file is added to \((folder as NSString?)?.lastPathComponent ?? "a folder")"
            }
        }

        /// Whether it is set up enough to run.
        public var isComplete: Bool {
            switch kind {
            case .manual: return true
            case .schedule: return (0...23).contains(hour ?? -1) && (0...59).contains(minute ?? -1)
                && (weekdays ?? []).allSatisfy { (1...7).contains($0) }
            case .interval: return (everyHours ?? 0) >= 1
            case .appOpened: return app != nil
            case .fileAdded: return folder != nil
            }
        }

        /// The next time a schedule or interval fires strictly after `date`. For an interval,
        /// `date` is the last run (or when it was set). Events and manual triggers return nil.
        public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
            guard isComplete else { return nil }
            switch kind {
            case .schedule:
                let days = Set(weekdays ?? [])
                var from = date
                // A week and a day covers every weekday pattern, across a change to or from daylight time.
                for _ in 0..<9 {
                    guard let next = calendar.nextDate(after: from, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                                       matchingPolicy: .nextTime, direction: .forward) else { return nil }
                    if days.isEmpty || days.contains(calendar.component(.weekday, from: next)) { return next }
                    from = next
                }
                return nil
            case .interval:
                return date.addingTimeInterval(TimeInterval((everyHours ?? 1) * 3600))
            case .manual, .appOpened, .fileAdded:
                return nil
            }
        }

        /// The latest time a schedule should have fired at or before `date`, if any in the last week.
        public func lastScheduledRun(atOrBefore date: Date, calendar: Calendar = .current) -> Date? {
            guard kind == .schedule, isComplete else { return nil }
            var candidate: Date?
            var from = date.addingTimeInterval(-8 * 24 * 3600)
            while let next = nextRun(after: from, calendar: calendar), next <= date {
                candidate = next
                from = next
            }
            return candidate
        }
    }
}
