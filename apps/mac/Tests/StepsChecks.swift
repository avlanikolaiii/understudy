import Foundation
import UnderstudyCore

@main
struct StepsChecks {
    static func main() {
        typealias A = RecordedAction
        // The shape of a real take: Dock click, the switch it caused, shortcuts typed as letters,
        // ⌘K, text in a field, Return, then another app.
        let take = Recording(id: UUID(), startedAt: Date(), duration: 30, actions: [
            A(t: 4.6, kind: .click, app: "Dock", bundle: "com.apple.dock", element: .init(role: "AXDockItem", title: "Superhuman")),
            A(t: 4.6, kind: .appSwitch, app: "Superhuman", bundle: "com.superhuman.electron", window: "Superhuman"),
            A(t: 7.5, kind: .typing, app: "Superhuman", bundle: "com.superhuman.electron", element: .init(role: "AXWebArea"), text: "gi"),
            A(t: 17.4, kind: .shortcut, app: "Superhuman", bundle: "com.superhuman.electron", text: "⌘K"),
            A(t: 18.4, kind: .typing, app: "Superhuman", bundle: "com.superhuman.electron", element: .init(role: "AXTextField"), text: "open"),
            A(t: 19.0, kind: .shortcut, app: "Superhuman", bundle: "com.superhuman.electron", text: "↩"),
            A(t: 22.5, kind: .appSwitch, app: "Dia", bundle: "company.thebrowser.dia"),
        ], notes: [], video: "screen.mov")
        let steps = StepsFromRecording.steps(from: take)
        // Letters pressed in the inbox (not a text field) are shortcuts: one key press each, never typed text.
        // "open" went into the command bar's text field, so it is typed.
        precondition(steps.map(\.intent) == ["Open Superhuman", "Press G", "Press I", "Press ⌘K", "Type “open”", "Press ↩", "Open Dia"])
        precondition(steps[0].target.app == "com.superhuman.electron" && steps[0].parameters["action"] == "activate")
        precondition(steps.map { $0.parameters["action"] ?? "" } == ["activate", "keys", "keys", "keys", "type", "keys", "activate"])
        precondition(!steps.contains { $0.parameters["action"] == "focus" })   // nothing clicks into a field that wasn't clicked
        precondition(steps.map(\.id) == (1...7).map { "step-\($0)" })
        // Pauses from the recording, between 0.3 and 5 seconds.
        precondition(steps.map { $0.parameters["after"] ?? "" } == ["0.0", "2.9", "0.3", "5.0", "1.0", "0.6", "3.5"])
        precondition(steps.allSatisfy { !$0.effect.needsApproval && $0.executor != .unsupported })

        // Watch now records such keys as key presses with their key code; the step keeps it.
        let archive = StepsFromRecording.steps(from: Recording(id: UUID(), startedAt: Date(), duration: 1, actions: [
            A(t: 0, kind: .shortcut, app: "Superhuman", bundle: "com.superhuman.electron", text: "E", keyCode: 14),
            A(t: 1, kind: .typing, app: "Superhuman", element: .init(role: "AXGroup"), text: "Ab"),
        ], notes: [], video: nil))
        precondition(archive.map(\.intent) == ["Press E", "Press ⇧A", "Press B"] && archive[0].parameters["keyCode"] == "14")
        precondition(archive[0].effect == .write && !archive[0].effect.needsApproval)
        precondition(A(t: 0, kind: .typing, app: "x", element: .init(role: "AXTextArea")).element!.isTextInput)
        precondition(!A(t: 0, kind: .typing, app: "x", element: .init(role: "AXWebArea")).element!.isTextInput)

        // Named controls are pressed; sending or deleting waits for approval; unnamed clicks need the mouse.
        func click(_ role: String, _ title: String?) -> SkillDefinition.Step {
            StepsFromRecording.steps(from: Recording(id: UUID(), startedAt: Date(), duration: 1, actions: [
                A(t: 0, kind: .click, app: "Mail", bundle: "com.apple.mail", element: .init(role: role, title: title)),
            ], notes: [], video: nil))[0]
        }
        let send = click("AXButton", "Send")
        precondition(send.executor == .accessibility && send.parameters["action"] == "press" && send.effect == .send)
        precondition(send.target.role == "AXButton" && send.target.title == "Send" && send.effect.needsApproval)
        precondition(click("AXButton", "Mover a la papelera").effect == .delete)
        precondition(click("AXButton", "Enviar ahora").effect == .send)
        precondition(click("AXButton", "Sender details").effect == .write)   // whole words only
        precondition(click("AXTextField", "Subject").parameters["action"] == "focus")
        let unnamed = click("AXWebArea", nil)
        precondition(unnamed.executor == .unsupported && unnamed.parameters["reason"]?.contains("mouse") == true)
        precondition(click("AXGroup", "Toolbar").executor == .unsupported)

        // A click is identified by the element and the text around it, never by position: nine
        // "Play" buttons are told apart by their album. A double-click stays one step.
        let spotify = StepsFromRecording.steps(from: Recording(id: UUID(), startedAt: Date(), duration: 3, actions: [
            A(t: 0, kind: .click, app: "Spotify", bundle: "com.spotify.client",
              element: .init(role: "AXButton", description: "Play", context: "Bloom", pressable: true)),
            A(t: 1, kind: .click, app: "Spotify", bundle: "com.spotify.client",
              element: .init(role: "AXRow", title: "Liked Songs", context: "Recents", pressable: true)),
            A(t: 1.2, kind: .click, app: "Spotify", bundle: "com.spotify.client",
              element: .init(role: "AXRow", title: "Liked Songs", context: "Recents", pressable: true), clicks: 2),
            A(t: 2, kind: .click, app: "Spotify", bundle: "com.spotify.client", element: .init(role: "AXScrollArea"),
              hiddenIn: "com.spotify.client"),
        ], notes: [], video: nil))
        precondition(spotify.count == 3)
        precondition(spotify[0].intent == "Press “Play” (“Bloom”) in Spotify" && spotify[0].parameters["context"] == "Bloom")
        precondition(spotify[0].target.role == "AXButton" && spotify[0].target.title == "Play" && spotify[0].parameters["action"] == "press")
        precondition(spotify[1].parameters["clicks"] == "2" && spotify[1].intent.hasPrefix("Double-click “Liked Songs”"))
        precondition(spotify[2].executor == .unsupported && spotify[2].parameters["reveal"] == "com.spotify.client")
        precondition(!spotify.contains { $0.parameters.keys.contains { $0.lowercased().contains("position") || $0 == "x" || $0 == "y" } })

        // Steps added by hand run like recorded ones.
        let open = ManualStep.openApp(name: "Spotify", bundle: "com.spotify.client")
        precondition(open.parameters["action"] == "activate" && open.target.app == "com.spotify.client" && open.id.hasPrefix("manual-"))
        let key = ManualStep.keys("⌘K", keyCode: 40, app: "Superhuman", bundle: nil)
        precondition(key.parameters["keyCode"] == "40" && key.intent == "Press ⌘K" && !key.effect.needsApproval)
        precondition(ManualStep.keys("⌘↩", keyCode: nil, app: nil, bundle: nil).effect.needsApproval)
        // Shortcuts that send or delete wait for the person's OK, recorded or added by hand.
        for keys in ["⌘↩", "⇧⌘D", "⌫", "⌘⌫", "⇧⌘⌫", "#"] {
            precondition(StepsFromRecording.effect(ofKeys: keys).needsApproval, keys)
            precondition(ManualStep.keys(keys, keyCode: nil, app: nil, bundle: nil).effect.needsApproval, keys)
        }
        precondition(StepsFromRecording.effect(ofKeys: "⇧⌘D") == .send && StepsFromRecording.effect(ofKeys: "⌫") == .delete)
        for keys in ["E", "⇧E", "⌘K", "↩", "↓", "⇥"] { precondition(!StepsFromRecording.effect(ofKeys: keys).needsApproval, keys) }
        precondition(StepsFromRecording.effect(ofKeys: "E") == .write && StepsFromRecording.effect(ofKeys: "↓") == .read)
        precondition(ManualStep.waitText("Bloom", app: "Spotify", bundle: nil).parameters["action"] == "waitText")
        precondition(ManualStep.waitSeconds(3).parameters["seconds"] == "3" && ManualStep.openLink("spotify:album:x").parameters["link"] == "spotify:album:x")
        precondition(open.id != ManualStep.openApp(name: "Spotify", bundle: nil).id)

        // Variables: {name} in what a step types or opens, filled when it runs.
        let steps2 = [ManualStep.type("Hello {client}, week {week}", app: "Mail", bundle: nil), ManualStep.openLink("https://x.test/{client}"),
                      ManualStep.type("no vars {", app: nil, bundle: nil)]
        precondition(Variables.names(in: steps2) == ["client", "week"])
        let filled = Variables.fill(steps2[0], with: ["client": "Norte", "week": "39"])
        precondition(filled.parameters["text"] == "Hello Norte, week 39" && filled.intent == "Type “Hello Norte, week 39”")
        precondition(Variables.fill(steps2[1], with: ["week": "1"]).parameters["link"] == "https://x.test/{client}")   // no value: left as written
        precondition(steps.allSatisfy { $0.parameters["t"] != nil })   // recorded steps know their moment in the video

        // Passwords and selections can't be replayed; ⌘↩ sends.
        let other = StepsFromRecording.steps(from: Recording(id: UUID(), startedAt: Date(), duration: 1, actions: [
            A(t: 0, kind: .typing, app: "Safari", element: .init(role: "AXTextField", subrole: "AXSecureTextField"), text: "secret"),
            A(t: 1, kind: .selection, app: "Numbers", cells: "D5=1 E5=2"),
            A(t: 2, kind: .shortcut, app: "Mail", text: "⌘↩"),
        ], notes: [], video: nil))
        precondition(other[0].executor == .unsupported && other[0].intent == "Type a password" && other[0].parameters["text"] == nil)
        precondition(other[1].executor == .unsupported && other[1].intent == "Select D5, E5 in Numbers")
        precondition(other[2].effect == .send)

        // The definition keeps its recording link through a round trip.
        var definition = SkillDefinition(steps: steps, recording: take.id)
        definition.rules = SkillDefinition.Rule.lines("Only on weekdays")
        let restored = try! JSONDecoder().decode(SkillDefinition.self, from: JSONEncoder().encode(definition))
        precondition(restored == definition && restored.recording == take.id)
        precondition(StepsFromRecording.steps(from: Recording(id: UUID(), startedAt: Date(), duration: 0, actions: [], notes: [], video: nil)).isEmpty)
        print("PASS: manual steps, variables, a real take becomes seven steps, letters outside text fields are key presses, clicks found by element and context (not position), double-clicks, apps that hide their contents, Dock clicks merge, pauses kept, named presses, approval words, unsupported clicks, passwords, selections, recording link")
    }
}
