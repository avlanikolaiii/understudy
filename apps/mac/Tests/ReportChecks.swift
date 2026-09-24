import Foundation

@main
struct ReportChecks {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }

    static func decimal(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    // Synthetic rows only. Each parameter supplies Search's values; the other
    // channels have real zeroes unless deliberately overridden in a test.
    static func week(_ number: Int, impressions: String = "1000", clicks: String = "100",
                     spend: String = "100", leads: String = "10", videoSpend: String = "0") -> String {
        let start = number == 0 ? "2026-08-10" : "2026-08-17"
        return """
        \(number),\(start),Search,\(impressions),\(clicks),\(spend),\(leads)
        \(number),\(start),Social,0,0,0,0
        \(number),\(start),Video,0,0,\(videoSpend),0
        """
    }

    static func csv(_ weeks: String...) -> String {
        "week,week_start,channel,impressions,clicks,spend_usd,leads\n" + weeks.joined(separator: "\n") + "\n"
    }

    static func report(_ csv: String) throws -> WeeklyReport {
        try ReportEngine.report(csv: csv, week: 1, client: "Synthetic client")
    }

    static func line(_ metric: String, in report: WeeklyReport) -> String {
        report.markdown.components(separatedBy: "\n").first { $0.hasPrefix("| \(metric) |") } ?? ""
    }

    static func assertRejects(_ csv: String, _ reason: String) throws {
        do {
            _ = try report(csv)
        } catch is ReportEngineError { return }
        throw Failure(description: "Expected invalid input to throw: \(reason)")
    }

    static func main() throws {
        // Run from the repository root. Read only the explicitly named teaching files.
        let source = try String(contentsOfFile: "data/fixtures/teaching/sheet/campaign_data.csv", encoding: .utf8)
        for number in 1...3 {
            let path = "data/fixtures/teaching/reports/week-0\(number).md"
            let expected = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: "\n")
            let result = try ReportEngine.report(csv: source, week: number, client: "Norte Studio")
            let actual = result.markdown.components(separatedBy: "\n")
            for index in [0, 2] {
                try require(actual[index] == expected[index], "\(path):\(index + 1) expected \(expected[index]); got \(actual[index])")
            }
            let expectedTable = expected.enumerated().filter { $0.element.hasPrefix("|") }
            let actualTable = actual.filter { $0.hasPrefix("|") }
            try require(expectedTable.count == 8 && actualTable.count == 8, "Week \(number): table must have exactly eight lines")
            for (entry, generated) in zip(expectedTable, actualTable) {
                try require(entry.element == generated, "\(path):\(entry.offset + 1) expected \(entry.element); got \(generated)")
            }
            try require(result.isComplete && result.missingCells.isEmpty, "Week \(number) is complete")
            try require(result.markdown.components(separatedBy: "[AI step: not connected yet]").count == 4,
                        "Exactly three judgment placeholders")
            try require(result.markdown.hasSuffix("\n"), "Markdown ends with a newline")
            let again = try ReportEngine.report(csv: source, week: number, client: "Norte Studio")
            try require(result.markdown == again.markdown, "Repeated rendering is deterministic")
        }
        print("PASS: exact title, dates, and all table lines for teaching weeks 1, 2, 3")

        // 1 / 32 * 100 = 3.125%; spend 1.005 / one lead = $1.005.
        let ties = try report(csv(week(0), week(1, impressions: "32", clicks: "1", spend: "1.005", leads: "1")))
        try require(line("CTR", in: ties).contains("| 3.13% |"), "CTR .xx5 rounds half-up")
        try require(line("Ad spend", in: ties).contains("| $1.01 |"), "Spend .xx5 rounds half-up")
        try require(line("Cost per lead", in: ties).contains("| $1.01 |"), "CPL .xx5 rounds half-up")
        try require(ties.thisWeek.adSpend.number == decimal("1.005"), "Raw spend is unrounded")
        try require(ties.thisWeek.ctr.number == decimal("3.125"), "Raw CTR is unrounded")
        let split = csv(week(1, spend: "0.335", leads: "1", videoSpend: "0.335"))
            .replacingOccurrences(of: "Social,0,0,0,0", with: "Social,0,0,0.335,0")
        let summed = try report(split)
        try require(summed.thisWeek.adSpend.number == decimal("1.005"), "No rounding before summing channels")
        try require(line("Ad spend", in: summed).contains("| $1.01 |"), "Round only after summing")
        let changes = try report(csv(week(0, impressions: "800", clicks: "800"),
                                     week(1, impressions: "810", clicks: "790")))
        try require(line("Impressions", in: changes).hasSuffix("| +1.3% |"), "Positive 1.25% half-up")
        try require(line("Clicks", in: changes).hasSuffix("| −1.3% |"), "Negative -1.25% half-up away from zero, Unicode minus")
        try require(changes.changes.clicks.number == decimal("-1.25"), "Raw changes are unrounded")
        let rateTies = try report(csv(week(0, impressions: "240", clicks: "80", spend: "80", leads: "240"),
                                      week(1, impressions: "240", clicks: "79", spend: "81", leads: "240")))
        try require(line("CTR", in: rateTies).hasSuffix("| −1.3% |"), "Repeating CTR quotients preserve the negative half-up tie")
        try require(line("Cost per lead", in: rateTies).hasSuffix("| +1.3% |"), "Repeating CPL quotients preserve the positive half-up tie")
        try require(rateTies.changes.ctr.number == decimal("-1.25") && rateTies.changes.costPerLead.number == decimal("1.25"),
                    "Rate changes use source totals without rounding repeating quotients")
        let unchanged = try report(csv(week(0), week(1)))
        try require(line("CTR", in: unchanged).hasSuffix("| +0.0% |"), "Zero change is signed")
        print("PASS: Decimal half-up ties, both change signs, unrounded figures, and sum-before-rounding")

        let missingCSV = csv(week(0), week(1, videoSpend: ""))
        let missing = try report(missingCSV)
        try require(!missing.isComplete && missing.missingCells.count == 1, "One blank cell makes an incomplete report")
        let cell = missing.missingCells[0]
        try require(cell.week == 1 && cell.channel == "Video" && cell.column == "spend_usd", "Identify the actual missing cell")
        try require(missing.markdown.hasPrefix("# Synthetic client · Weekly update · Week 1 (DRAFT, incomplete)\n"), "Draft title suffix")
        try require(missing.markdown.contains("## Missing data\n\n- Week 1: Video · spend_usd\n\n## Summary"), "Missing section at the top names channel and column")
        try require(line("Ad spend", in: missing) == "| Ad spend | [missing: needs input] | $100.00 | [missing: depends on ad spend] |", "Never display a partial spend total")
        try require(line("Cost per lead", in: missing) == "| Cost per lead | [missing: depends on ad spend] | $10.00 | [missing: depends on ad spend] |", "Propagate missing spend through CPL and change")
        try require(missing.thisWeek.adSpend.number == nil && missing.thisWeek.costPerLead.number == nil
                    && missing.changes.adSpend.number == nil && missing.changes.costPerLead.number == nil,
                    "No invented numeric values behind missing placeholders")
        try require(missing.thisWeek.leads.number == 10 && missing.thisWeek.ctr.number == 10, "Unaffected metrics still compute")
        let zeroSpend = try report(csv(week(0), week(1, spend: "0")))
        try require(zeroSpend.isComplete && zeroSpend.thisWeek.adSpend.number == 0, "Zero spend is not missing")
        try require(line("Ad spend", in: zeroSpend) == "| Ad spend | $0.00 | $100.00 | −100.0% |", "Real zero spend formats as money")
        let otherMissing = try report(csv(week(0), week(1, impressions: "", clicks: "", leads: "", videoSpend: "")))
        try require(otherMissing.missingCells.count == 4, "Every blank source cell is named")
        try require(otherMissing.thisWeek.impressions == .missingInput && otherMissing.thisWeek.clicks == .missingInput
                    && otherMissing.thisWeek.leads == .missingInput && otherMissing.thisWeek.ctr == .missingInput,
                    "Missing non-spend sources propagate too")
        print("PASS: missing Video spend, draft and cell labels, dependent figures, and real zeroes")

        let noLeads = try report(csv(week(0), week(1, leads: "0")))
        try require(noLeads.isComplete && noLeads.thisWeek.costPerLead == .noLeads, "Zero leads does not mean missing")
        try require(line("Cost per lead", in: noLeads) == "| Cost per lead | n/a (no leads) | $10.00 | n/a |", "No leads display and undefined CPL change")
        let noPrevious = try report(csv(week(1)))
        try require(noPrevious.isComplete && noPrevious.lastWeek.adSpend == .unavailable, "Absent previous week has no fabricated values")
        for metric in ["Impressions", "Clicks", "CTR", "Ad spend", "Leads", "Cost per lead"] {
            try require(line(metric, in: noPrevious).hasSuffix("| n/a | n/a |"), "\(metric): absent last week gives n/a")
        }
        let previousZero = try report(csv(week(0, impressions: "0", clicks: "0", spend: "0", leads: "0"), week(1)))
        for metric in ["Impressions", "Clicks", "CTR", "Ad spend", "Leads", "Cost per lead"] {
            try require(line(metric, in: previousZero).hasSuffix("| n/a |"), "\(metric): zero/undefined last week gives n/a")
        }
        let zeroCPL = try report(csv(week(0, spend: "0"), week(1)))
        try require(line("Cost per lead", in: zeroCPL).hasSuffix("| $0.00 | n/a |"), "Last week's numeric zero CPL gives n/a change")
        let previousMissing = try report(csv(week(0, videoSpend: ""), week(1)))
        try require(line("Ad spend", in: previousMissing) == "| Ad spend | $100.00 | [missing: needs input] | n/a |", "Missing previous spend means n/a change")
        try require(line("Cost per lead", in: previousMissing) == "| Cost per lead | $10.00 | [missing: depends on ad spend] | n/a |", "Missing previous CPL means n/a change")
        try require(previousMissing.missingCells.first?.week == 0 && !previousMissing.isComplete, "Prior blank cells are also disclosed")
        print("PASS: no leads, absent/zero/missing prior figures, and undefined denominators")

        let ordinary = csv(week(0), week(1))
        let quoted = "\u{FEFF}" + ordinary.components(separatedBy: "\n").filter { !$0.isEmpty }.map {
            $0.components(separatedBy: ",").map { "\"\($0)\"" }.joined(separator: ",")
        }.joined(separator: "\r\n")
        try require(try report(quoted).markdown == report(ordinary).markdown, "Quoted CSV, CRLF, BOM, and no final newline")
        let reordered = ordinary.components(separatedBy: "\n")
        let shuffled = reordered[0] + "\n" + reordered.dropFirst().filter { !$0.isEmpty }.reversed().joined(separator: "\n")
        try require(try report(shuffled).markdown == report(ordinary).markdown, "Row order does not affect output")
        try assertRejects(csv(week(1, spend: "bad")), "malformed number must not become zero")
        try assertRejects(csv(week(1, clicks: "1.5")), "counts must be integers")
        try assertRejects(csv(week(1, spend: "1e3")), "plain decimals only")
        try assertRejects(csv(week(1, spend: "-1")), "nonnegative source figures")
        try assertRejects(csv(week(1, spend: "1234567890123456789012345678901234567890123456789")), "no silently truncated Decimal input")
        try assertRejects(csv(week(1)) + "1,2026-08-17,Video,0,0,0,0\n", "duplicate channel")
        try assertRejects(csv(week(1)).replacingOccurrences(of: "1,2026-08-17,Video,0,0,0,0\n", with: ""), "absent channel is not zero")
        try assertRejects(csv(week(1)).replacingOccurrences(of: "Video,0,0,0,0", with: "Video,0,0,0"), "short row")
        try assertRejects(csv(week(1)).replacingOccurrences(of: "2026-08-17,Video", with: "2026-08-24,Video"), "inconsistent dates")
        try assertRejects(csv(week(1)).replacingOccurrences(of: "2026-08-17", with: "2026-08-18"), "not Monday")
        try assertRejects(csv(week(1)).replacingOccurrences(of: "2026-08-17", with: "2026-02-30"), "invalid date")
        try assertRejects(csv(week(0), week(1)).replacingOccurrences(of: "2026-08-10", with: "2026-08-03"), "nonadjacent weeks")
        try assertRejects(ordinary + "\"unterminated", "malformed quoting")
        try assertRejects(ordinary.replacingOccurrences(of: "Search", with: "\"Search\"extra"), "characters after closing quote")
        print("PASS: CSV normalization, deterministic row order, and invalid-input rejection")
    }
}
