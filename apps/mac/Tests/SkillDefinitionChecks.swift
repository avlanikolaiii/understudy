import Foundation
import UnderstudyCore

@main
struct SkillDefinitionChecks {
    static func main() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()

        // A learned skill survives the round trip exactly, and says it's version 1.
        let learned = SkillDefinition(
            trigger: .init(kind: .manual, detail: "Every Monday"),
            inputs: [.init(id: "figures", name: "Campaign figures", connector: "file", location: "campaign_data.csv")],
            steps: [
                .init(id: "read", intent: "Read the week's figures", executor: .connector, effect: .read, evidence: .readBack),
                .init(id: "send", intent: "Send the report", executor: .appleScript,
                      target: .init(app: "com.apple.mail", role: "AXButton", title: "Send"), effect: .send, evidence: .none),
            ],
            rules: SkillDefinition.Rule.lines("Flag missing figures.\n\n  Keep it short.  "),
            output: .init(connector: "file", location: "report.md"))
        let data = try encoder.encode(learned)
        let restored = try decoder.decode(SkillDefinition.self, from: data)
        precondition(restored == learned && restored.schemaVersion == 1 && !restored.simulated)
        precondition(restored.rules.map(\.text) == ["Flag missing figures.", "Keep it short."])
        precondition(restored.notes == "Flag missing figures.\nKeep it short.")
        precondition(!restored.steps[0].effect.needsApproval && restored.steps[1].effect.needsApproval)

        // Version 0, the prototype's {rules, simulated} object in `skills.definition`, migrates.
        let legacy = try decoder.decode(SkillDefinition.self, from: Data(#"{"rules":"a\nb","simulated":true}"#.utf8))
        precondition(legacy.schemaVersion == 1 && legacy.simulated && legacy.steps.isEmpty && legacy.notes == "a\nb")
        let legacyNoFlag = try decoder.decode(SkillDefinition.self, from: Data(#"{"rules":"x"}"#.utf8))
        precondition(legacyNoFlag.simulated)

        // A format newer than this app is refused, never half-read.
        var newer = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        newer["schemaVersion"] = SkillDefinition.currentVersion + 1
        var refused = false
        do { _ = try decoder.decode(SkillDefinition.self, from: JSONSerialization.data(withJSONObject: newer)) } catch { refused = true }
        precondition(refused)

        // Prepared skills (today's simulated Watch) are labeled as such.
        precondition(SkillDefinition.prepared(notes: "x").simulated)
        print("PASS: skill definition v1 round trip, rule lines, approval effects, v0 migration, newer format refused")
    }
}
