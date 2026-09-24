import Foundation

@main struct WorkspaceChecks {
    @MainActor static func main() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-workspace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var time: TimeInterval = 0
        let capture = ScriptedCapture()
        let watch = WatchSession(source: capture, folder: folder, now: { time })
        let ui = WorkspaceState()
        ui.startWatch(watch)
        precondition(ui.page == .teach && ui.teachingStep == 1 && watch.isWatching)
        time = 7; watch.advance(); capture.emitNext()
        watch.ruleDraft = "Keep figures unchanged"
        // Reopening the app's flow must not restart the shared notch session.
        ui.startWatch(watch)
        precondition(watch.elapsedSeconds == 7 && watch.actions.count == 1)
        ui.reviewWatch(watch)
        precondition(!watch.isWatching && ui.teachingStep == 2)
        precondition(ui.rules.contains("Keep figures unchanged"))
        let notes = ui.rules
        ui.reviewWatch(watch)
        precondition(ui.rules == notes)
        // A session started through the other entry point can be resumed here.
        watch.dismiss(); watch.start(automaticTicks: false)
        time = 12; watch.advance()
        ui.page = .home
        ui.showTeaching(watch: watch)
        precondition(ui.page == .teach && ui.teachingStep == 1 && watch.elapsedSeconds == 5)
        watch.stop()
        print("PASS: shared Watch resume, app teaching navigation, stop-to-review, pending-note transfer, and duplicate-note prevention")
    }
}
