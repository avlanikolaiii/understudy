// Held-out evaluation of ReportEngine: the only code allowed to read data/evaluation/.
// For each held-out week it compares the deterministic parts of the report (title, date line,
// and every numbers-table line) with the expected report, and prints scores only, never content.
//   swiftc apps/mac/Sources/Understudy/ReportEngine.swift qa/eval-holdout.swift -o /tmp/eval && /tmp/eval [out.json]
import Foundation

@main
struct EvalHoldout {
    static func main() throws {
        let root = URL(fileURLWithPath: "data/evaluation/holdout")
        let weeks = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("week-") }.sorted()
        var results: [[String: Any]] = []
        for folder in weeks {
            guard let number = Int(folder.dropFirst("week-".count)) else { continue }
            let dir = root.appendingPathComponent(folder)
            let sheets = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("sheet").path)
            let expectedFiles = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("expected").path)
            // The campaign sheet, named as in the teaching fixtures (the notes tab is a separate CSV).
            let csv = sheets.contains("campaign_data.csv")
                ? try String(contentsOf: dir.appendingPathComponent("sheet/campaign_data.csv"), encoding: .utf8) : nil
            guard let csv, let expectedName = expectedFiles.first(where: { $0.hasSuffix(".md") }) else {
                results.append(["week": number, "error": "missing sheet or expected report"]); continue
            }
            let expected = try String(contentsOf: dir.appendingPathComponent("expected/\(expectedName)"), encoding: .utf8)
                .components(separatedBy: "\n")
            do {
                let actual = try ReportEngine.report(csv: csv, week: number, client: "Norte Studio").markdown
                    .components(separatedBy: "\n")
                let expectedTable = expected.filter { $0.hasPrefix("|") }
                let actualTable = actual.filter { $0.hasPrefix("|") }
                let tableMatches = zip(expectedTable, actualTable).filter { $0 == $1 }.count
                results.append([
                    "week": number,
                    "title": actual.first == expected.first,
                    "dates": actual.count > 2 && expected.count > 2 && actual[2] == expected[2],
                    "tableLines": expectedTable.count,
                    "tableMatches": expectedTable.count == actualTable.count ? tableMatches : 0,
                ])
            } catch {
                results.append(["week": number, "error": "engine threw: \(error)"])
            }
        }
        let passed = results.filter {
            ($0["title"] as? Bool) == true && ($0["dates"] as? Bool) == true && ($0["tableMatches"] as? Int) == ($0["tableLines"] as? Int)
        }.count
        for r in results {
            if let error = r["error"] { print("week \(r["week"]!): ERROR \(error)"); continue }
            print("week \(r["week"]!): title \(r["title"]! as! Bool ? "✓" : "✗") · dates \(r["dates"]! as! Bool ? "✓" : "✗") · table \(r["tableMatches"]!)/\(r["tableLines"]!)")
        }
        print("eval-holdout: \(passed)/\(results.count) weeks exact")
        if CommandLine.arguments.count > 1 {
            let data = try JSONSerialization.data(withJSONObject: ["suite": "eval-holdout", "passed": passed, "total": results.count, "weeks": results],
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        exit(passed == results.count ? 0 : 1)
    }
}
