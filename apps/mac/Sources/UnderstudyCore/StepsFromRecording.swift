import Foundation

/// Turns a recording into steps the app can run again, exactly as they were done (no AI).
/// Each step says how it runs without the mouse: open the app, press a named control, type, or
/// press keys. A click with nothing to name it by, a selection, or a password can't be replayed
/// yet, so it becomes an `unsupported` step the person sees in the review.
///
/// Parameters used by the executors:
/// - `action`: `activate`, `press`, `focus`, `type`, `keys`
/// - `app`: the app's name (also used to open it when its bundle id isn't known)
/// - `text` (type), `keys` (keys, e.g. "⌘K", "↩", or "E"), `keyCode` (the exact key, when recorded),
///   `window` (the window it happened in)
/// - `after`: seconds to wait before the step, from the pause in the recording
/// - `context`: text near the control that tells it apart from others with the same name
/// - `clicks`: "2" for a double-click
/// - `reason`: why an unsupported step can't run; `reveal`: the bundle id of an app that hides
///   its contents until Understudy reopens it in a mode that shows them
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
        for action in recording.actions.flatMap(keyPresses) {
            let after = steps.isEmpty ? 0 : min(5, max(0.3, action.t - previousTime))
            previousTime = action.t
            guard var step = step(for: action) else { continue }
            // Opening the same app twice in a row (a Dock click, then the switch it caused) is one step.
            if let last = steps.last, last.parameters["action"] == "activate", step.parameters["action"] == "activate",
               last.parameters["app"] == step.parameters["app"] {
                steps[steps.count - 1].target.app = last.target.app ?? step.target.app
                continue
            }
            // The second click of a double-click makes the step before it a double-click.
            if (action.clicks ?? 1) > 1, let last = steps.last, last.parameters["action"] == step.parameters["action"],
               last.target == step.target, last.parameters["context"] == step.parameters["context"] {
                steps[steps.count - 1].parameters["clicks"] = "2"
                steps[steps.count - 1].intent = step.intent.replacingOccurrences(of: "Press ", with: "Double-click ")
                continue
            }
            step.parameters["after"] = String(format: "%.1f", after)
            // When it happened in the recording, to show that moment of the video next to the step.
            step.parameters["t"] = String(format: "%.2f", action.t)
            step.id = "step-\(steps.count + 1)"
            steps.append(step)
        }
        return steps
    }

    /// Keys "typed" where there was no text field (e.g. G then I in an inbox, recorded before
    /// Watch told them apart) are key presses: one step per key, never text typed into a field.
    static func keyPresses(_ action: RecordedAction) -> [RecordedAction] {
        guard action.kind == .typing, let element = action.element, !element.isTextInput, let text = action.text else { return [action] }
        return text.enumerated().map { offset, character in
            var key = action
            key.kind = .shortcut
            key.t = action.t + Double(offset) * 0.3
            key.text = (character.isUppercase ? "⇧" : "") + String(character).uppercased()
            key.element = nil; key.value = nil
            return key
        }
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
            if pressable.contains(role) || action.element?.pressable == true, let name {
                parameters["action"] = "press"
                if let context = action.element?.context { parameters["context"] = context }
                let place = action.element?.context.map { " (\(RecordedAction.quote($0, limit: 40)))" } ?? ""
                return Step(id: "", intent: "Press \(RecordedAction.quote(name))\(place) in \(action.app)", executor: .accessibility,
                            target: target, effect: effect(of: name), evidence: .none, parameters: parameters)
            }
            if let hidden = action.hiddenIn {
                parameters["reveal"] = hidden
                parameters["reason"] = "\(action.app) hides its buttons from Understudy. Reopen it for Understudy (button below), then record this part again."
            } else {
                parameters["reason"] = "This click has nothing to find it by (it needs the mouse). Delete the step, or record the task using the keyboard or named buttons."
            }
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
            if let code = action.keyCode { parameters["keyCode"] = String(code) }
            // A single key outside a text field is an app's shortcut (E archives in some mail apps):
            // it changes something, but it's pressed exactly as recorded.
            return Step(id: "", intent: "Press \(keys)", executor: .keyboard, target: .init(app: action.bundle),
                        effect: effect(ofKeys: keys), evidence: .none, parameters: parameters)
        case .selection:
            parameters["reason"] = "Selecting cells can't be replayed yet."
            return Step(id: "", intent: "Select \(action.cells.map(RecordedAction.addresses) ?? "cells") in \(action.app)",
                        executor: .unsupported, target: target, effect: .read, evidence: .none, parameters: parameters)
        }
    }

    /// Keys that send or delete in common apps: ⌘↩ sends (Mail's ⇧⌘D too); Delete, ⌘⌫, and #
    /// (Gmail, Superhuman) delete. Those steps wait for the person's OK.
    static let sendKeys: Set = ["⌘↩", "⇧⌘D", "⌥⌘↩", "⌃↩"]
    static let deleteKeys: Set = ["⌫", "⌦", "⌘⌫", "⌘⌦", "⇧⌘⌫", "⌥⇧⌘⌫", "⌥⌘⌫", "#", "⇧#", "⇧3"]

    /// What pressing `keys` does. A single letter outside a text field is an app's own shortcut
    /// (E archives in some mail apps): it changes something, pressed exactly as recorded.
    public static func effect(ofKeys keys: String) -> Step.Effect {
        if sendKeys.contains(keys) { return .send }
        if deleteKeys.contains(keys) { return .delete }
        let key = keys.drop { "⌃⌥⇧⌘".contains($0) }
        return key.count == 1 && key.first!.isLetter || keys.contains("⌘") ? .write : .read
    }

    /// What pressing a control named `name` does, judged by its words.
    static func effect(of name: String) -> Step.Effect {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        if words.contains(where: deleteWords.contains) { return .delete }
        if words.contains(where: sendWords.contains) { return .send }
        return .write
    }
}
