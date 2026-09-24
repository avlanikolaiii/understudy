import Foundation
import UnderstudyCore

@main
struct TriggerChecks {
    static func main() {
        typealias Trigger = SkillDefinition.Trigger
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!   // has daylight time
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        func parts(_ date: Date?) -> [Int] {
            guard let date else { return [] }
            let c = calendar.dateComponents([.month, .day, .hour, .minute, .weekday], from: date)
            return [c.month!, c.day!, c.hour!, c.minute!, c.weekday!]
        }

        // Every day at 9:00: later today if it's before 9, else tomorrow.
        let daily = Trigger(kind: .schedule, hour: 9, minute: 0)
        precondition(daily.summary == "Every day at 9:00" && daily.detail == "Every day at 9:00")
        precondition(parts(daily.nextRun(after: date(2026, 9, 24, 8, 30), calendar: calendar)) == [9, 24, 9, 0, 5])
        precondition(parts(daily.nextRun(after: date(2026, 9, 24, 9, 0), calendar: calendar)) == [9, 25, 9, 0, 6])
        // Month end, and across the change from daylight time (Nov 1, 2026) the wall time stays 9:00.
        precondition(parts(daily.nextRun(after: date(2026, 9, 30, 10), calendar: calendar)) == [10, 1, 9, 0, 5])
        precondition(parts(daily.nextRun(after: date(2026, 10, 31, 12), calendar: calendar)) == [11, 1, 9, 0, 1])

        // Weekdays: Friday evening → Monday.
        let weekdays = Trigger(kind: .schedule, hour: 18, minute: 30, weekdays: Trigger.weekdays)
        precondition(weekdays.summary == "Weekdays at 18:30")
        precondition(parts(weekdays.nextRun(after: date(2026, 9, 25, 19), calendar: calendar)) == [9, 28, 18, 30, 2])
        // Chosen days.
        let tueThu = Trigger(kind: .schedule, hour: 7, minute: 5, weekdays: [3, 5])
        precondition(tueThu.summary == "Tue, Thu at 7:05")
        precondition(parts(tueThu.nextRun(after: date(2026, 9, 24, 8), calendar: calendar)) == [9, 29, 7, 5, 3])

        // The latest time it should have run: for catching up after sleep.
        precondition(parts(daily.lastScheduledRun(atOrBefore: date(2026, 9, 24, 10), calendar: calendar)) == [9, 24, 9, 0, 5])
        precondition(parts(daily.lastScheduledRun(atOrBefore: date(2026, 9, 24, 8), calendar: calendar)) == [9, 23, 9, 0, 4])

        // Intervals count from the last run.
        let hourly = Trigger(kind: .interval, everyHours: 2)
        precondition(hourly.summary == "Every 2 hours" && hourly.nextRun(after: date(2026, 9, 24, 8)) == date(2026, 9, 24, 10))

        // Events and manual runs have no time; incomplete triggers never fire.
        let app = Trigger(kind: .appOpened, app: "com.superhuman.electron", appName: "Superhuman")
        precondition(app.summary == "When Superhuman opens" && app.nextRun(after: Date()) == nil && app.isComplete)
        let folder = Trigger(kind: .fileAdded, folder: "/Users/x/Downloads")
        precondition(folder.summary == "When a file is added to Downloads" && folder.isComplete)
        precondition(!Trigger(kind: .appOpened).isComplete && !Trigger(kind: .fileAdded).isComplete)
        precondition(!Trigger(kind: .schedule, hour: 25, minute: 0).isComplete)
        precondition(Trigger(kind: .schedule, hour: 25, minute: 0).nextRun(after: Date()) == nil)
        precondition(Trigger.manual.nextRun(after: Date()) == nil)

        // Stored triggers from before (kind + detail only) still load; new fields round-trip.
        let old = try! JSONDecoder().decode(Trigger.self, from: Data(#"{"kind":"manual","detail":"When you start it"}"#.utf8))
        precondition(old == .manual)
        let restored = try! JSONDecoder().decode(Trigger.self, from: JSONEncoder().encode(Trigger(kind: .schedule, hour: 9, minute: 15, weekdays: [2], device: "mac-1")))
        precondition(restored.device == "mac-1" && restored.weekdays == [2] && restored.summary == "Mon at 9:15")
        print("PASS: daily, weekdays, chosen days, month end, daylight time, catch-up, intervals, events, incomplete, old format")
    }
}
