import Foundation

/// Steps a person adds by hand in the step editor, next to the recorded ones. They run the same
/// way: no mouse, and nothing typed into a field unless the step says so.
public enum ManualStep {
    public typealias Step = SkillDefinition.Step

    public enum Kind: String, CaseIterable, Sendable {
        case openApp, keys, type, waitText, waitSeconds, openLink, command

        public var title: String {
            switch self {
            case .openApp: "Open an app"
            case .keys: "Press keys"
            case .type: "Type text"
            case .waitText: "Wait until text shows"
            case .waitSeconds: "Wait some seconds"
            case .openLink: "Open a link or file"
            case .command: "App command"
            }
        }
    }

    public static func openApp(name: String, bundle: String?) -> Step {
        Step(id: newID(), intent: "Open \(name)", executor: .appleScript, target: .init(app: bundle), effect: .read,
             evidence: .readBack, parameters: ["action": "activate", "app": name])
    }

    /// `keys` as Watch records them ("⌘K", "↩", "E"); `keyCode` when it was captured from a key press.
    public static func keys(_ keys: String, keyCode: Int?, app: String?, bundle: String?) -> Step {
        var parameters = ["action": "keys", "keys": keys, "app": app ?? ""]
        if let keyCode { parameters["keyCode"] = String(keyCode) }
        return Step(id: newID(), intent: "Press \(keys)", executor: .keyboard, target: .init(app: bundle),
                    effect: StepsFromRecording.effect(ofKeys: keys), evidence: .none, parameters: parameters)
    }

    /// Typed into whatever has focus in the app, as a recorded Type step is.
    public static func type(_ text: String, app: String?, bundle: String?) -> Step {
        Step(id: newID(), intent: "Type \(RecordedAction.quote(text))", executor: .keyboard, target: .init(app: bundle),
             effect: .write, evidence: .readBack, parameters: ["action": "type", "text": text, "app": app ?? ""])
    }

    public static func waitText(_ text: String, app: String?, bundle: String?, timeout: Int = 10) -> Step {
        Step(id: newID(), intent: "Wait until \(RecordedAction.quote(text)) shows", executor: .accessibility,
             target: .init(app: bundle), effect: .read, evidence: .readBack,
             parameters: ["action": "waitText", "text": text, "app": app ?? "", "timeout": String(timeout)])
    }

    public static func waitSeconds(_ seconds: Int) -> Step {
        Step(id: newID(), intent: "Wait \(seconds) s", executor: .compute, effect: .read, evidence: .none,
             parameters: ["action": "waitSeconds", "seconds": String(seconds)])
    }

    /// A web link, an app link (spotify:…), or a file path, opened by its default app.
    public static func openLink(_ link: String) -> Step {
        Step(id: newID(), intent: "Open \(RecordedAction.quote(link, limit: 48))", executor: .file, effect: .read,
             evidence: .readBack, parameters: ["action": "open", "link": link])
    }

    static func newID() -> String { "manual-" + UUID().uuidString.prefix(8).lowercased() }
}

/// `{name}` placeholders in what a step types or opens, filled with values asked when the skill
/// runs (or given by its trigger, like the file that arrived).
public enum Variables {
    /// The parameters that can hold placeholders.
    static let fields = ["text", "link", "playlist", "path", "to", "subject", "body"]

    /// Placeholder names in the steps, in order of first use.
    public static func names(in steps: [SkillDefinition.Step]) -> [String] {
        var names: [String] = []
        for step in steps {
            for field in fields {
                for name in tokens(in: step.parameters[field] ?? "") where !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// The step with its placeholders filled. A placeholder without a value stays as written.
    public static func fill(_ step: SkillDefinition.Step, with values: [String: String]) -> SkillDefinition.Step {
        guard !values.isEmpty else { return step }
        var filled = step
        for field in fields {
            if let text = filled.parameters[field] { filled.parameters[field] = replace(text, values) }
        }
        filled.intent = replace(step.intent, values)
        return filled
    }

    static func tokens(in text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            let name = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name.count <= 30, name.first!.isLetter, !name.contains("{") { found.append(name) }
            rest = rest[rest.index(after: close)...]
        }
        return found
    }

    static func replace(_ text: String, _ values: [String: String]) -> String {
        values.reduce(text) { result, pair in result.replacingOccurrences(of: "{\(pair.key)}", with: pair.value) }
    }
}
