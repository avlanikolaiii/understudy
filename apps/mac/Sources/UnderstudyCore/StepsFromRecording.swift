import Foundation

/// Turns a recording into steps the app can run again, exactly as they were done (no AI).
/// Each step says how it runs without the mouse: open the app, press a named control, type, or
/// press keys. A click with nothing to name it by, a selection, or a password can't be replayed
/// yet, so it becomes an `unsupported` step the person sees in the review.
///
/// Parameters used by the executors:
/// - `action`: `activate`, `press`, `focus`, `type`, `keys`
/// - `app`: the app's name (also used to open it when its bundle id isn't known)
/// - `text` (type), `keys` (keys, e.g. "⌘K" or "↩"), `window` (the window it happened in)
/// - `after`: seconds to wait before the step, from the pause in the recording
/// - `reason`: why an unsupported step can't run
public enum StepsFromRecording {
    public typealias Step = SkillDefinition.Step

    /// Roles a click can target by name. A click on anything else needs the mouse.
    static let pressable: Set = ["AXButton", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton",
                                 "AXPopUpButton", "AXLink", "AXTab", "AXDisclosureTriangle", "AXMenuButton"]
    /// Roles where a click only puts the cursor in the field.
    static let fields: Set = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Words in a control's name or a key that mean the step sends, pays, or deletes something.
    /// Those steps wait for the person's OK.
    static let sendWords = ["send", "enviar", "submit", "post", "publish", "publicar", "pay", "pagar",
                            "buy", "comprar", "purchase", "transfer", "transferir", "reply", "responder"]
    static let deleteWords = ["delete", "borrar", "eliminar", "remove", "quitar", "trash", "papelera", "discard", "descartar"]

    public static func steps(from recording: Recording) -> [Step] {
        var steps: [Step] = []
        var previousTime = recording.actions.first?.t ?? 0
        for action in recording.actions {
            let after = steps.isEmpty ? 0 : min(5, max(0.3, action.t - previousTime))
            previousTime = action.t
            guard var step = step(for: action) else { continue }
            // Opening the same app twice in a row (a Dock click, then the switch it caused) is one step.
            if let last = steps.last, last.parameters["action"] == "activate", step.parameters["action"] == "activate",
               last.parameters["app"] == step.parameters["app"] {
                steps[steps.count - 1].target.app = last.target.app ?? step.target.app
                continue
            }
            step.parameters["after"] = String(format: "%.1f", after)
            step.id = "step-\(steps.count + 1)"
            steps.append(step)
        }
        return steps
    }

    static func step(for action: RecordedAction) -> Step? {
        var parameters = ["app": action.app]
        if let window = action.window { parameters["window"] = window }
        let target = SkillDefinition.Target(app: action.bundle, role: action.element?.role,
                                            title: action.element?.title ?? action.element?.description,
                                            identifier: action.element?.identifier)
        switch action.kind {
        case .appSwitch:
            parameters["action"] = "activate"
            return Step(id: "", intent: "Open \(action.app)", executor: .appleScript,
                        target: .init(app: action.bundle), effect: .read, evidence: .readBack, parameters: parameters)
        case .click:
            let role = action.element?.role ?? ""
            let name = action.element?.name
            if role == "AXDockItem", let name {
                // A Dock click opens that app; its bundle comes from the switch that follows.
                return Step(id: "", intent: "Open \(name)", executor: .appleScript, target: .init(),
                            effect: .read, evidence: .readBack, parameters: ["action": "activate", "app": name])
            }
            if fields.contains(role), let name {
                parameters["action"] = "focus"
                return Step(id: "", intent: "Click in \(RecordedAction.quote(name))", executor: .accessibility,
                            target: target, effect: .read, evidence: .readBack, parameters: parameters)
            }
            if pressable.contains(role), let name {
                parameters["action"] = "press"
                return Step(id: "", intent: "Press \(RecordedAction.quote(name)) in \(action.app)", executor: .accessibility,
                            target: target, effect: effect(of: name), evidence: .none, parameters: parameters)
            }
            parameters["reason"] = "This click has nothing to find it by (it needs the mouse). Delete the step, or record the task using the keyboard or named buttons."
            return Step(id: "", intent: "Click in \(action.app)\(name.map { " on " + RecordedAction.quote($0) } ?? "")",
                        executor: .unsupported, target: target, effect: .write, evidence: .none, parameters: parameters)
        case .typing:
            guard let text = action.text else {
                parameters["reason"] = "Passwords are never recorded, so this can't be typed again."
                return Step(id: "", intent: "Type a password", executor: .unsupported, target: target,
                            effect: .write, evidence: .none, parameters: parameters)
            }
            parameters["action"] = "type"
            parameters["text"] = text
            return Step(id: "", intent: "Type \(RecordedAction.quote(text))", executor: .keyboard, target: target,
                        effect: .write, evidence: .readBack, parameters: parameters)
        case .shortcut:
            let keys = action.text ?? ""
            parameters["action"] = "keys"
            parameters["keys"] = keys
            return Step(id: "", intent: "Press \(keys)", executor: .keyboard, target: .init(app: action.bundle),
                        effect: keys == "⌘↩" ? .send : keys == "⌘⌫" ? .delete : .read, evidence: .none, parameters: parameters)
        case .selection:
            parameters["reason"] = "Selecting cells can't be replayed yet."
            return Step(id: "", intent: "Select \(action.cells.map(RecordedAction.addresses) ?? "cells") in \(action.app)",
                        executor: .unsupported, target: target, effect: .read, evidence: .none, parameters: parameters)
        }
    }

    /// What pressing a control named `name` does, judged by its words.
    static func effect(of name: String) -> Step.Effect {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: deleteWords.contains) { return .delete }
        if words.contains(where: sendWords.contains) { return .send }
        return .write
    }
}
