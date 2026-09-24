import Foundation

/// Commands apps offer for themselves on this Mac (AppleScript, or macOS opening a link), from a
/// fixed, vetted list: a step never runs a script someone wrote. Nothing on screen is looked for,
/// so they work with the app's window moved, hidden, or minimized.
///
/// A command step's parameters: `action` = "command", `command` = the case's raw value, and one
/// entry per field (`link`, `playlist`, `path`, `browser`, `to`, `subject`, `body`).
public enum AppCommand: String, CaseIterable, Codable, Sendable {
    case spotifyPlay, spotifyPause, spotifyNext, spotifyPrevious
    case musicPlaylist, musicPause, musicNext
    case finderOpen, finderReveal
    case browserOpen
    case mailDraft

    public typealias Step = SkillDefinition.Step

    public struct Field: Equatable, Sendable {
        public let key: String
        public let label: String
        /// For a choice: (value, label) pairs. Empty for text.
        public let options: [Option]
        public struct Option: Equatable, Sendable {
            public let value: String
            public let label: String
        }
    }

    /// How a command runs.
    public enum Invocation: Equatable, Sendable {
        /// AppleScript that returns what it did, in words.
        case script(String)
        /// A link opened by an app (nil: its default app).
        case open(link: String, app: String?)
        /// A file shown selected in Finder.
        case reveal(path: String)
    }

    public struct Problem: Error, Equatable {
        public let message: String
        public init(message: String) { self.message = message }
    }

    public static let spotify = "com.spotify.client"
    public static let music = "com.apple.Music"
    public static let finder = "com.apple.finder"
    public static let mail = "com.apple.mail"
    public static let browsers: [Field.Option] = [
        .init(value: "", label: "Default browser"), .init(value: "com.apple.Safari", label: "Safari"),
        .init(value: "com.google.Chrome", label: "Chrome"), .init(value: "company.thebrowser.dia", label: "Dia"),
        .init(value: "company.thebrowser.Browser", label: "Arc"),
    ]

    public var appName: String {
        switch self {
        case .spotifyPlay, .spotifyPause, .spotifyNext, .spotifyPrevious: "Spotify"
        case .musicPlaylist, .musicPause, .musicNext: "Music"
        case .finderOpen, .finderReveal: "Finder"
        case .browserOpen: "Browser"
        case .mailDraft: "Mail"
        }
    }

    /// The app it controls (a browser command uses the chosen one).
    public var bundle: String? {
        switch self {
        case .spotifyPlay, .spotifyPause, .spotifyNext, .spotifyPrevious: Self.spotify
        case .musicPlaylist, .musicPause, .musicNext: Self.music
        case .finderOpen, .finderReveal: Self.finder
        case .browserOpen: nil
        case .mailDraft: Self.mail
        }
    }

    public var title: String {
        switch self {
        case .spotifyPlay: "Spotify: play a song, album, or playlist link"
        case .spotifyPause: "Spotify: pause"
        case .spotifyNext: "Spotify: next track"
        case .spotifyPrevious: "Spotify: previous track"
        case .musicPlaylist: "Music: play a playlist"
        case .musicPause: "Music: pause"
        case .musicNext: "Music: next track"
        case .finderOpen: "Finder: open a folder"
        case .finderReveal: "Finder: show a file"
        case .browserOpen: "Browser: open a link"
        case .mailDraft: "Mail: create a draft (not sent)"
        }
    }

    public var fields: [Field] {
        switch self {
        case .spotifyPlay: [Field(key: "link", label: "Spotify link (Share → Copy link), or spotify:album:…", options: [])]
        case .musicPlaylist: [Field(key: "playlist", label: "Playlist name", options: [])]
        case .finderOpen: [Field(key: "path", label: "Folder, e.g. ~/Downloads", options: [])]
        case .finderReveal: [Field(key: "path", label: "File, e.g. {file}", options: [])]
        case .browserOpen: [Field(key: "link", label: "https://…", options: []), Field(key: "browser", label: "Browser", options: Self.browsers)]
        case .mailDraft: [Field(key: "to", label: "To (addresses, separated by commas)", options: []),
                          Field(key: "subject", label: "Subject", options: []), Field(key: "body", label: "Message", options: [])]
        case .spotifyPause, .spotifyNext, .spotifyPrevious, .musicPause, .musicNext: []
        }
    }

    /// Playing music changes something the person hears; a draft is written but never sent.
    public var effect: Step.Effect {
        switch self {
        case .finderOpen, .finderReveal, .browserOpen: .read
        default: .write
        }
    }

    /// What the step does, in words, for the step list.
    public func intent(_ values: [String: String]) -> String {
        let value = { (key: String) in RecordedAction.quote(values[key] ?? "", limit: 48) }
        switch self {
        case .spotifyPlay: return "Play \(value("link")) in Spotify"
        case .spotifyPause: return "Pause Spotify"
        case .spotifyNext: return "Next track in Spotify"
        case .spotifyPrevious: return "Previous track in Spotify"
        case .musicPlaylist: return "Play the playlist \(value("playlist")) in Music"
        case .musicPause: return "Pause Music"
        case .musicNext: return "Next track in Music"
        case .finderOpen: return "Open the folder \(value("path"))"
        case .finderReveal: return "Show \(value("path")) in Finder"
        case .browserOpen:
            let browser = Self.browsers.first { $0.value == (values["browser"] ?? "") && !$0.value.isEmpty }?.label ?? "the browser"
            return "Open \(value("link")) in \(browser)"
        case .mailDraft: return "Draft an email to \(value("to")) in Mail (not sent)"
        }
    }

    /// The step, with its values. Values may hold `{name}` placeholders, checked when it runs.
    public func step(_ values: [String: String]) -> Step {
        var parameters = values.filter { key, _ in fields.contains { $0.key == key } }
        parameters["action"] = "command"
        parameters["command"] = rawValue
        parameters["app"] = appName
        let executor: Step.Executor = invocationKind == .script ? .appleScript : .file
        return Step(id: ManualStep.newID(), intent: intent(values), executor: executor, target: .init(app: bundle ?? values["browser"].flatMap { $0.isEmpty ? nil : $0 }),
                    effect: effect, evidence: .readBack, parameters: parameters)
    }

    /// Why the values can't run, or nil. Placeholders pass until the run fills them.
    public func problem(_ values: [String: String]) -> String? {
        for field in fields where field.options.isEmpty && field.key != "body" && field.key != "subject" {
            if (values[field.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return "Fill in \(field.label.lowercased())." }
        }
        if !Variables.tokens(in: fields.map { values[$0.key] ?? "" }.joined(separator: " ")).isEmpty { return nil }
        do { _ = try invocation(values); return nil } catch let problem as Problem { return problem.message } catch { return "\(error)" }
    }

    private enum Kind { case script, open }
    private var invocationKind: Kind {
        switch self {
        case .finderOpen, .finderReveal, .browserOpen: .open
        default: .script
        }
    }

    /// How to run it with these values (placeholders already filled).
    public func invocation(_ values: [String: String]) throws -> Invocation {
        func text(_ key: String) -> String { (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        switch self {
        case .spotifyPlay:
            guard let uri = Self.spotifyURI(text("link")) else {
                throw Problem(message: "\(RecordedAction.quote(text("link"))) isn't a Spotify link. In Spotify, use Share → Copy link.")
            }
            return .script(Self.tell(Self.spotify, "play track \(Self.quoted(uri))", then: Self.nowPlaying))
        case .spotifyPause: return .script(Self.tell(Self.spotify, "pause", then: Self.nowPlaying))
        case .spotifyNext: return .script(Self.tell(Self.spotify, "next track", then: Self.nowPlaying))
        case .spotifyPrevious: return .script(Self.tell(Self.spotify, "previous track", then: Self.nowPlaying))
        case .musicPlaylist:
            guard !text("playlist").isEmpty else { throw Problem(message: "Name the playlist.") }
            return .script(Self.tell(Self.music, "play playlist \(Self.quoted(text("playlist")))", then: Self.nowPlaying))
        case .musicPause: return .script(Self.tell(Self.music, "pause", then: Self.nowPlaying))
        case .musicNext: return .script(Self.tell(Self.music, "next track", then: Self.nowPlaying))
        case .finderOpen, .finderReveal:
            let path = (text("path") as NSString).expandingTildeInPath
            guard path.hasPrefix("/") else { throw Problem(message: "\(RecordedAction.quote(text("path"))) isn't a path. Start it with / or ~.") }
            return self == .finderOpen ? .open(link: path, app: Self.finder) : .reveal(path: path)
        case .browserOpen:
            let link = text("link")
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw Problem(message: "\(RecordedAction.quote(link)) isn't a web link (https://…).")
            }
            let browser = text("browser")
            guard browser.isEmpty || Self.browsers.contains(where: { $0.value == browser }) else { throw Problem(message: "That browser isn't in the list.") }
            return .open(link: link, app: browser.isEmpty ? nil : browser)
        case .mailDraft:
            let addresses = text("to").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !addresses.isEmpty, addresses.allSatisfy(Self.isAddress) else {
                throw Problem(message: "\(RecordedAction.quote(text("to"))) isn't a list of email addresses.")
            }
            // A visible draft: sending stays a separate step that waits for the person's OK.
            let recipients = addresses.map { "make new to recipient at end of to recipients with properties {address:\(Self.quoted($0))}" }
            let body = """
                set draft to make new outgoing message with properties {subject:\(Self.quoted(values["subject"] ?? "")), content:\(Self.quoted(values["body"] ?? "")), visible:true}
                tell draft
                \(recipients.joined(separator: "\n"))
                end tell
                activate
                return "Draft to " & (address of first to recipient of draft) & " is open in Mail, not sent."
                """
            return .script(Self.tell(Self.mail, body, then: nil))
        }
    }

    /// Whether what the command reports back shows it worked.
    public func verified(_ report: String) -> Bool {
        switch self {
        case .spotifyPlay, .spotifyNext, .spotifyPrevious, .musicPlaylist, .musicNext: report.hasPrefix("Playing")
        case .spotifyPause, .musicPause: !report.hasPrefix("Playing")
        case .mailDraft: report.hasPrefix("Draft to")
        case .finderOpen, .finderReveal, .browserOpen: false
        }
    }

    // MARK: Spotify's own command instead of clicks

    /// A Spotify link or URI as the URI Spotify's AppleScript plays (spotify:album:ID).
    public static func spotifyURI(_ link: String) -> String? {
        let kinds: Set = ["track", "album", "playlist", "artist", "episode", "show"]
        let valid = { (kind: String, id: String) in
            kinds.contains(kind) && (1...64).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("spotify:") {
            let parts = trimmed.split(separator: ":").map(String.init)
            return parts.count == 3 && valid(parts[1], parts[2]) ? trimmed : nil
        }
        guard let url = URL(string: trimmed), url.host?.lowercased() == "open.spotify.com" else { return nil }
        // https://open.spotify.com/intl-es/album/ID?si=… → spotify:album:ID
        let path = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        guard path.count >= 2, valid(path[0], path[1]) else { return nil }
        return "spotify:\(path[0]):\(path[1])"
    }

    /// AppleScript that reads Spotify's current track: "spotify:track:ID\tName — Artist".
    public static let spotifyCurrentTrack = tell(spotify, "return (spotify url of current track) & tab & (name of current track) & \" — \" & (artist of current track)", then: nil)

    /// The steps with Spotify's clicks (and opening Spotify for them) replaced by one command
    /// that plays `uri`: it doesn't depend on Spotify's window at all. Nil when there are none.
    public static func replacingSpotifyClicks(in steps: [Step], with uri: String, name: String) -> [Step]? {
        let clicks = { (step: Step) in
            step.target.app == spotify && ["press", "focus", "activate"].contains(step.parameters["action"] ?? "")
        }
        guard steps.contains(where: { clicks($0) && $0.parameters["action"] != "activate" }),
              let first = steps.firstIndex(where: clicks) else { return nil }
        var command = AppCommand.spotifyPlay.step(["link": uri])
        command.intent = "Play \(RecordedAction.quote(name, limit: 48)) in Spotify"
        var result = steps.filter { !clicks($0) }
        result.insert(command, at: min(first, result.count))
        return result
    }

    // MARK: Script text

    /// Returns "Playing: Name — Artist" or "Not playing (paused)".
    static let nowPlaying = """
        delay 1
        if player state is playing then return "Playing: " & (name of current track) & " — " & (artist of current track)
        return "Not playing (" & (player state as text) & ")"
        """

    static func tell(_ bundle: String, _ body: String, then: String?) -> String {
        """
        with timeout of 15 seconds
        tell application id \(quoted(bundle))
        \(body)
        \(then ?? "")
        end tell
        end timeout
        """
    }

    /// An AppleScript string literal: the value can't end the string or add code.
    public static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func isAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains { $0.isWhitespace || "\"<>,;\\".contains($0) }
    }
}
