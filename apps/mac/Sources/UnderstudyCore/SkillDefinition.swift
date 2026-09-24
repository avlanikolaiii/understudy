import Foundation

/// A skill: the procedure Understudy runs itself. It is learned from a recording, reviewed by the
/// person, kept in their account (`skills.definition`), and executed by the app. It is never an
/// export for another AI app. The skill's name and client are stored beside it, not inside it.
///
/// Every stored format has a version. Version 0 is the prototype's `{rules, simulated}` object,
/// which decodes into version 1 with no steps.
public struct SkillDefinition: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    public var trigger: Trigger
    public var inputs: [Input]
    public var steps: [Step]
    public var rules: [Rule]
    public var output: Output?
    /// True when the skill was prepared by hand, not learned from a recording. The app labels it.
    public var simulated: Bool

    public init(trigger: Trigger = .manual, inputs: [Input] = [], steps: [Step] = [], rules: [Rule] = [],
                output: Output? = nil, simulated: Bool = false) {
        schemaVersion = Self.currentVersion
        self.trigger = trigger; self.inputs = inputs; self.steps = steps; self.rules = rules
        self.output = output; self.simulated = simulated
    }

    /// A skill with notes but no learned steps, as the prototype saves today.
    public static func prepared(notes: String) -> SkillDefinition {
        SkillDefinition(rules: Rule.lines(notes), simulated: true)
    }

    /// The notes as the person wrote them, one per line.
    public var notes: String { rules.map(\.text).joined(separator: "\n") }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, trigger, inputs, steps, rules, output, simulated
    }

    private enum LegacyKeys: String, CodingKey { case rules, simulated }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            self = .prepared(notes: try legacy.decodeIfPresent(String.self, forKey: .rules) ?? "")
            simulated = try legacy.decodeIfPresent(Bool.self, forKey: .simulated) ?? true
            return
        }
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                debugDescription: "Skill format \(version) is newer than this app understands (\(Self.currentVersion)). Update Understudy.")
        }
        schemaVersion = Self.currentVersion
        trigger = try c.decode(Trigger.self, forKey: .trigger)
        inputs = try c.decode([Input].self, forKey: .inputs)
        steps = try c.decode([Step].self, forKey: .steps)
        rules = try c.decode([Rule].self, forKey: .rules)
        output = try c.decodeIfPresent(Output.self, forKey: .output)
        simulated = try c.decode(Bool.self, forKey: .simulated)
    }
}

extension SkillDefinition {
    /// When the skill runs. Scheduled runs come later.
    public struct Trigger: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case manual }
        public var kind: Kind
        /// In plain words, e.g. "Every Monday, when the week's figures are in".
        public var detail: String

        public init(kind: Kind, detail: String) { self.kind = kind; self.detail = detail }
        public static let manual = Trigger(kind: .manual, detail: "When you start it")
    }

    /// Something the skill reads, e.g. a sheet through a connector or a file on this Mac.
    public struct Input: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Which connector reads it: "file", "google.sheets", …
        public var connector: String
        /// Where: a path, a URL, a range.
        public var location: String

        public init(id: String, name: String, connector: String, location: String) {
            self.id = id; self.name = name; self.connector = connector; self.location = location
        }
    }

    /// Where the result goes.
    public struct Output: Codable, Equatable, Sendable {
        public var connector: String
        public var location: String

        public init(connector: String, location: String) { self.connector = connector; self.location = location }
    }

    /// One step of the procedure, and how Understudy performs it without taking the mouse.
    public struct Step: Codable, Equatable, Sendable, Identifiable {
        /// In order of preference: an API connector, the app's scripting, Accessibility actions,
        /// the keyboard. `unsupported` marks a step no executor can do yet (e.g. one that needs the mouse).
        public enum Executor: String, Codable, Sendable {
            case connector, appleScript, accessibility, keyboard, compute, ai, file, unsupported
        }

        /// What the step changes. Rehearsal runs only `read` steps; `send` and `delete` wait for approval.
        public enum Effect: String, Codable, Sendable {
            case read, write, send, delete
            public var needsApproval: Bool { self == .send || self == .delete }
        }

        /// How the result is checked. `readBack` reads the result again from its source.
        public enum Evidence: String, Codable, Sendable { case readBack, none }

        public var id: String
        /// What the step does, in plain words.
        public var intent: String
        public var executor: Executor
        public var target: Target
        public var effect: Effect
        public var evidence: Evidence
        public var parameters: [String: String]

        public init(id: String, intent: String, executor: Executor, target: Target = Target(), effect: Effect,
                    evidence: Evidence, parameters: [String: String] = [:]) {
            self.id = id; self.intent = intent; self.executor = executor; self.target = target
            self.effect = effect; self.evidence = evidence; self.parameters = parameters
        }
    }

    /// The app and element a step acts on, as seen while recording.
    public struct Target: Codable, Equatable, Sendable {
        /// Bundle identifier, e.g. "com.apple.iWork.Numbers".
        public var app: String?
        public var role: String?
        public var title: String?
        public var identifier: String?

        public init(app: String? = nil, role: String? = nil, title: String? = nil, identifier: String? = nil) {
            self.app = app; self.role = role; self.title = title; self.identifier = identifier
        }
    }

    /// A note the person gave while teaching. Corrections apply to this workflow only for now.
    public struct Rule: Codable, Equatable, Sendable {
        public enum Scope: String, Codable, Sendable { case workflow }
        public var text: String
        public var scope: Scope

        public init(text: String, scope: Scope = .workflow) { self.text = text; self.scope = scope }

        /// One rule per non-empty line.
        public static func lines(_ text: String) -> [Rule] {
            text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { Rule(text: $0) }
        }
    }
}
