import AppKit
import UnderstudyCore

/// Runs the AppleScript of a vetted App command (see `AppCommand`) off the main thread, with a
/// time limit. macOS asks once per app to let Understudy control it (Automation).
enum AppleScripts {
    static let automationNeeded = "Understudy isn't allowed to control %@. Turn it on in System Settings → Privacy & Security → Automation → Understudy."

    /// `done` gets what the script returned, or why it failed, on the main thread.
    static func run(_ source: String, app: String, timeout: TimeInterval = 20, done: @escaping @MainActor (Result<String, AppCommand.Problem>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let input = Pipe(), output = Pipe(), errors = Pipe()
            process.standardInput = input; process.standardOutput = output; process.standardError = errors
            let result: Result<String, AppCommand.Problem>
            do {
                try process.run()
                input.fileHandleForWriting.write(Data(source.utf8))
                try? input.fileHandleForWriting.close()
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { usleep(50_000) }
                if process.isRunning {
                    process.terminate()
                    result = .failure(.init(message: "\(app) didn't answer within \(Int(timeout)) s."))
                } else {
                    let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    if process.terminationStatus == 0 {
                        result = .success(said)
                    } else if error.contains("-1743") {
                        result = .failure(.init(message: String(format: automationNeeded, app)))
                    } else if error.contains("-1728") || error.contains("-1719") {
                        result = .failure(.init(message: "\(app) has nothing playing to read."))
                    } else {
                        let reason = error.components(separatedBy: "execution error: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        result = .failure(.init(message: "\(app) refused the command\(reason.isEmpty ? "" : ": \(reason)")."))
                    }
                }
            } catch {
                result = .failure(.init(message: "AppleScript couldn't start: \(error.localizedDescription)."))
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result) } }
        }
    }
}

/// Reads the track Spotify is playing, for "Use Spotify's own command instead".
@MainActor
final class SpotifyNowPlaying: ObservableObject {
    static let shared = SpotifyNowPlaying()
    @Published private(set) var reading = false
    @Published private(set) var problem: String?

    func read(_ found: @escaping (_ uri: String, _ name: String) -> Void) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: AppCommand.spotify).isEmpty else {
            problem = "Open Spotify and start the song or album first."; return
        }
        reading = true; problem = nil
        AppleScripts.run(AppCommand.spotifyCurrentTrack, app: "Spotify", timeout: 10) { [weak self] result in
            guard let self else { return }
            self.reading = false
            switch result {
            case .success(let said):
                let parts = said.components(separatedBy: "\t")
                guard parts.count == 2, let uri = AppCommand.spotifyURI(parts[0]) else {
                    self.problem = "Spotify isn't playing anything Understudy can link to."; return
                }
                found(uri, parts[1])
            case .failure(let problem):
                self.problem = problem.message
            }
        }
    }
}
