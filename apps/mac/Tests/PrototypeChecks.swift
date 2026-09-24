import Foundation

@main
struct PrototypeChecks {
    static func main() throws {
        let skill = Skill(name: "QA weekly report", client: "Synthetic client", rules: "Review before sharing.")
        let complete = SampleEngine.rehearse(skill: skill, scenario: .complete)
        precondition(complete.status == "Ready for your review")
        precondition(complete.report.contains("$1,250.00") && complete.report.contains("$10.00"))
        precondition(complete.report.contains("Synthetic client"))
        precondition(complete.report.contains("AI interpretation and enforcement are not connected."))
        let missing = SampleEngine.rehearse(skill: skill, scenario: .missing)
        precondition(missing.status == "Needs input")
        precondition(missing.report.contains("DRAFT, incomplete"))
        precondition(missing.report.contains("[missing: needs input]"))
        precondition(missing.report.contains("[missing: depends on ad spend]"))
        precondition(!missing.report.contains("$1,250.00") && !missing.report.contains("$10.00"))
        precondition(missing.exportPath == nil)
        let data = try JSONEncoder().encode([complete, missing])
        let restored = try JSONDecoder().decode([Receipt].self, from: data)
        precondition(restored.map(\.report) == [complete.report, missing.report])
        precondition(restored.map(\.id) == [complete.id, missing.id])
        precondition(missing.steps.first?.status == "Blocked · needs you" && !missing.readyToSend)

        // Sample mode storage: round trip, and files from the earlier prototype still open.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("understudy-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = LocalStore(url: dir.appendingPathComponent("library.json"))
        let empty = try file.load()
        precondition(empty == nil)
        try file.save(.init(skills: [.sample, skill], receipts: [missing]))
        let loaded = try file.load()!
        precondition(loaded.skills.map(\.id) == [Skill.sample.id, skill.id] && loaded.skills[0].isSample && !loaded.skills[1].isSample)
        precondition(loaded.receipts.first?.report == missing.report)
        let legacy = #"{"skills":[{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Weekly client update","client":"Norte Studio","rules":"x"}],"receipts":[]}"#
        try Data(legacy.utf8).write(to: file.url)
        let migrated = try file.load()
        precondition(migrated?.skills[0].isSample == true && migrated?.skills[0].rules == "x")
        precondition(migrated?.skills[0].definition.simulated == true)
        // Saving writes the current format; a file from a newer Understudy is refused, not overwritten.
        try file.save(migrated!)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as! [String: Any]
        precondition(saved["version"] as? Int == LocalStore.Contents.currentVersion)
        precondition(((saved["skills"] as! [[String: Any]])[0]["definition"] as! [String: Any])["schemaVersion"] as? Int == 1)
        try Data(#"{"version":99,"skills":[],"receipts":[]}"#.utf8).write(to: file.url)
        var newer = false
        do { _ = try file.load() } catch { newer = true }
        precondition(newer)
        try Data("not json".utf8).write(to: file.url)
        var unreadable = false
        do { _ = try file.load() } catch { unreadable = true }
        precondition(unreadable)
        print("PASS: complete sample, missing-data propagation, simulation disclosure, receipt persistence, and versioned sample-mode storage")
    }
}
