import Foundation

@main
struct PrototypeChecks {
    static func main() throws {
        let skill = DemoSkill(name: "QA weekly report", client: "Synthetic client", rules: "Review before sharing.")
        let complete = DemoEngine.rehearse(skill: skill, scenario: .complete)
        precondition(complete.status == "Ready for your review")
        precondition(complete.report.contains("$1,250.00") && complete.report.contains("$10.00"))
        precondition(complete.report.contains("Synthetic client"))
        precondition(complete.report.contains("AI interpretation and enforcement are not connected."))
        let missing = DemoEngine.rehearse(skill: skill, scenario: .missing)
        precondition(missing.status == "Needs input")
        precondition(missing.report.contains("DRAFT, incomplete"))
        precondition(missing.report.contains("[missing: needs input]"))
        precondition(missing.report.contains("[missing: depends on ad spend]"))
        precondition(!missing.report.contains("$1,250.00") && !missing.report.contains("$10.00"))
        precondition(missing.exportPath == nil)
        let data = try JSONEncoder().encode([complete, missing])
        let restored = try JSONDecoder().decode([DemoReceipt].self, from: data)
        precondition(restored.map(\.report) == [complete.report, missing.report])
        precondition(restored.map(\.id) == [complete.id, missing.id])
        print("PASS: complete sample, missing-data propagation, simulation disclosure, and receipt persistence")
    }
}
