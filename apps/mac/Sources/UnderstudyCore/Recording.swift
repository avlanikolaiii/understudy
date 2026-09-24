import Foundation

/// What Watch recorded while the person taught: the actions they took, on the same clock as the
/// screen video, and the notes they added. It stays on the Mac; learning reads it.
public struct Recording: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = Recording.currentVersion
    public var id: UUID
    public var startedAt: Date
    public var duration: Double
    public var actions: [RecordedAction]
    public var notes: [String]
    /// The screen video's file name in the recording's folder, if the screen was recorded.
    public var video: String?

    public init(id: UUID, startedAt: Date, duration: Double, actions: [RecordedAction], notes: [String], video: String?) {
        self.id = id; self.startedAt = startedAt; self.duration = duration
        self.actions = actions; self.notes = notes; self.video = video
    }
}

/// One thing the person did: switched app, clicked, typed, pressed a shortcut, or selected cells.
public struct RecordedAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case appSwitch, click, typing, shortcut, selection }

    /// What was clicked or edited, as Accessibility describes it.
    public struct Element: Codable, Equatable, Sendable {
        public var role: String?
        public var subrole: String?
        public var title: String?
        public var description: String?
        public var identifier: String?

        public init(role: String? = nil, subrole: String? = nil, title: String? = nil,
                    description: String? = nil, identifier: String? = nil) {
            self.role = role; self.subrole = subrole; self.title = title
            self.description = description; self.identifier = identifier
        }

        public var isSecure: Bool { role == "AXSecureTextField" || subrole == "AXSecureTextField" }
        /// A place that takes typed text. Keys pressed anywhere else (an inbox, a list, a web
        /// page) are shortcuts, like E to archive, and are replayed as key presses, never as text.
        public var isTextInput: Bool { isSecure || Self.textRoles.contains(role ?? "") }
        public static let textRoles: Set = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXSecureTextField"]
        /// The words a person would use for it: its title, else its description.
        public var name: String? { [title, description].compactMap { $0 }.first { !$0.isEmpty } }
    }

    /// Seconds since the recording started, on the video's clock.
    public var t: Double
    public var kind: Kind
    public var app: String
    public var bundle: String?
    public var window: String?
    public var element: Element?
    /// Typed text, or a shortcut such as "⌘C".
    public var text: String?
    /// The field's value after the action.
    public var value: String?
    /// Selected spreadsheet cells, e.g. "D5=1200 E5=48".
    public var cells: String?
    /// For a key press: the key's virtual key code, so a run presses exactly that key.
    public var keyCode: Int?

    public init(t: Double, kind: Kind, app: String, bundle: String? = nil, window: String? = nil, element: Element? = nil,
                text: String? = nil, value: String? = nil, cells: String? = nil, keyCode: Int? = nil) {
        self.t = t; self.kind = kind; self.app = app; self.bundle = bundle; self.window = window
        self.element = element; self.text = text; self.value = value; self.cells = cells; self.keyCode = keyCode
        redactSecureFields()
    }

    /// Password fields are recorded by role only: nothing typed into them and no value.
    public mutating func redactSecureFields() {
        guard element?.isSecure == true else { return }
        text = nil; value = nil
    }

    /// What happened, in a few plain words (the notch and the timeline show it).
    public var summary: String {
        switch kind {
        case .appSwitch:
            return "opened \(Self.quote(window ?? app))"
        case .click:
            return element?.name.map { "clicked \(Self.quote($0))" } ?? "clicked"
        case .typing:
            if element?.isSecure == true { return "typed a password (not recorded)" }
            return text.map { "typed \(Self.quote($0))" } ?? "typed"
        case .shortcut:
            return "pressed \(text ?? "a shortcut")"
        case .selection:
            return "selected \(cells.map { Self.addresses($0) } ?? "cells")"
        }
    }

    /// "D5=1200 E5=48" → "D5, E5".
    public static func addresses(_ cells: String) -> String {
        cells.split(separator: " ").map { $0.split(separator: "=").first.map(String.init) ?? String($0) }.joined(separator: ", ")
    }

    public static func quote(_ text: String, limit: Int = 32) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return "“" + (flat.count > limit ? String(flat.prefix(limit)) + "…" : flat) + "”"
    }
}
