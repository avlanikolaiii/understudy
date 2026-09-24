import Foundation

/// An unrounded figure, or the reason a figure cannot be computed.
public enum ReportFigure: Sendable, Equatable {
    case value(Decimal)
    case missingInput
    case missingAdSpend
    case noLeads
    case unavailable

    public var number: Decimal? {
        if case let .value(number) = self { return number }
        return nil
    }
}

public struct ReportFigures: Sendable, Equatable {
    public let impressions: ReportFigure
    public let clicks: ReportFigure
    public let ctr: ReportFigure
    public let adSpend: ReportFigure
    public let leads: ReportFigure
    public let costPerLead: ReportFigure

    fileprivate var ordered: [ReportFigure] {
        [impressions, clicks, ctr, adSpend, leads, costPerLead]
    }

    fileprivate init(_ figures: [ReportFigure]) {
        impressions = figures[0]
        clicks = figures[1]
        ctr = figures[2]
        adSpend = figures[3]
        leads = figures[4]
        costPerLead = figures[5]
    }
}

public struct ReportMissingCell: Sendable, Equatable {
    public let week: Int
    public let channel: String
    public let column: String
}

public struct WeeklyReport: Sendable {
    public let markdown: String
    /// Source-data completeness only. AI judgment sections remain placeholders.
    public let isComplete: Bool
    public let missingCells: [ReportMissingCell]
    public let thisWeek: ReportFigures
    public let lastWeek: ReportFigures
    /// Percent changes, computed from unrounded figures.
    public let changes: ReportFigures
}

public enum ReportEngineError: Error, Sendable, Equatable, LocalizedError {
    case invalidCSV(String)
    case invalidCell(row: Int, column: String, value: String)
    case invalidWeek(Int, String)
    case arithmetic(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidCSV(reason): return "Invalid CSV: \(reason)"
        case let .invalidCell(row, column, value):
            return "Invalid CSV row \(row), \(column): \(value)"
        case let .invalidWeek(week, reason): return "Invalid week \(week): \(reason)"
        case let .arithmetic(reason): return "Decimal arithmetic failed: \(reason)"
        }
    }
}

/// Pure, synchronous computation. No file access, network, or shared mutable state.
public enum ReportEngine {
    public static func report(
        csv: String, week: Int, client: String, agency: String = "Faro Creative"
    ) throws -> WeeklyReport {
        let rows = try parse(csv)
        let current = rows.filter { $0.week == week }
        let previous = rows.filter { week > 0 && $0.week == week - 1 }
        guard !current.isEmpty else { throw ReportEngineError.invalidWeek(week, "no rows") }
        try validate(current, week: week)
        if !previous.isEmpty { try validate(previous, week: week - 1) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = current[0].date
        if let prior = previous.first,
           calendar.date(byAdding: .day, value: -7, to: start) != prior.date {
            throw ReportEngineError.invalidWeek(week, "previous week must start seven days earlier")
        }
        let end = calendar.date(byAdding: .day, value: 6, to: start)!
        let dateDisplay = DateFormatter()
        dateDisplay.locale = Locale(identifier: "en_US_POSIX")
        dateDisplay.calendar = calendar
        dateDisplay.timeZone = calendar.timeZone
        dateDisplay.dateFormat = "MMM d, yyyy"

        let now = try figures(current)
        let last = try figures(previous)
        let changes = try ReportFigures(now.ordered.indices.map {
            // Cross-multiply source totals for rate changes. Subtracting two
            // repeating Decimal quotients can move an exact half-up tie.
            if $0 == 2 {
                return try rateChange(now.ctr, last.ctr, now.clicks, now.impressions, last.clicks, last.impressions)
            }
            if $0 == 5 {
                return try rateChange(now.costPerLead, last.costPerLead, now.adSpend, now.leads, last.adSpend, last.leads)
            }
            return try change(now.ordered[$0], last.ordered[$0], adSpend: $0 == 3)
        })
        let numericColumns = ["impressions", "clicks", "spend_usd", "leads"]
        let missing = (current + previous).sorted {
            $0.week == $1.week ? $0.channel < $1.channel : $0.week < $1.week
        }.flatMap { row in
            numericColumns.indices.compactMap { index in
                row.values[index] == nil
                    ? ReportMissingCell(week: row.week, channel: row.channel, column: numericColumns[index])
                    : nil
            }
        }
        let suffix = missing.isEmpty ? "" : " (DRAFT, incomplete)"
        let missingSection = missing.isEmpty ? "" : "## Missing data\n\n" + missing.map {
            "- Week \($0.week): \($0.channel) · \($0.column)"
        }.joined(separator: "\n") + "\n\n"
        let labels = ["Impressions", "Clicks", "CTR", "Ad spend", "Leads", "Cost per lead"]
        let table = labels.indices.map { index in
            "| \(labels[index]) | \(display(now.ordered[index], metric: index)) | \(display(last.ordered[index], metric: index)) | \(display(changes.ordered[index], metric: index, change: true)) |"
        }.joined(separator: "\n")
        let markdown = """
        # \(client) · Weekly update · Week \(week)\(suffix)

        \(dateDisplay.string(from: start)) to \(dateDisplay.string(from: end)) · Prepared by \(agency)

        \(missingSection)## Summary

        [AI step: not connected yet]

        ## Numbers

        | Metric | This week | Last week | Change |
        |---|---:|---:|---:|
        \(table)

        ## Highlight

        [AI step: not connected yet]

        ## Next week

        [AI step: not connected yet]

        """
        return WeeklyReport(markdown: markdown, isComplete: missing.isEmpty, missingCells: missing,
                            thisWeek: now, lastWeek: last, changes: changes)
    }

    private struct Row {
        let week: Int
        let date: Date
        let channel: String
        let values: [Decimal?]
    }

    private static func parse(_ csv: String) throws -> [Row] {
        let records = try csvRecords(csv)
        let columns = ["week", "week_start", "channel", "impressions", "clicks", "spend_usd", "leads"]
        guard records.first == columns else {
            throw ReportEngineError.invalidCSV("expected header \(columns.joined(separator: ","))")
        }
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX")
        dates.calendar = Calendar(identifier: .gregorian)
        dates.timeZone = TimeZone(secondsFromGMT: 0)!
        dates.dateFormat = "yyyy-MM-dd"
        dates.isLenient = false
        return try records.dropFirst().enumerated().map { index, fields in
            let rowNumber = index + 2
            guard fields.count == columns.count else {
                throw ReportEngineError.invalidCSV("row \(rowNumber) has \(fields.count) fields; expected 7")
            }
            func invalid(_ column: Int) -> ReportEngineError {
                .invalidCell(row: rowNumber, column: columns[column], value: fields[column])
            }
            guard fields[0].range(of: "^[0-9]+$", options: .regularExpression) != nil,
                  let week = Int(fields[0]) else { throw invalid(0) }
            guard let date = dates.date(from: fields[1]), dates.string(from: date) == fields[1] else {
                throw invalid(1)
            }
            guard ["Search", "Social", "Video"].contains(fields[2]) else { throw invalid(2) }
            let values: [Decimal?] = try (3...6).map { column in
                let cell = fields[column]
                if cell.isEmpty { return nil }
                let pattern = column == 5 ? "^[0-9]+(?:\\.[0-9]+)?$" : "^[0-9]+$"
                guard cell.range(of: pattern, options: .regularExpression) != nil,
                      let value = Decimal(string: cell, locale: Locale(identifier: "en_US_POSIX")),
                      !value.isNaN else { throw invalid(column) }
                // Decimal(string:) can silently truncate excessive precision. Reject it.
                func canonical(_ string: String) -> String {
                    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
                    let whole = String(parts[0].drop(while: { $0 == "0" }))
                    let fraction = parts.count > 1 ? String(parts[1].reversed().drop(while: { $0 == "0" }).reversed()) : ""
                    return (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
                }
                var copy = value
                guard canonical(NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))) == canonical(cell) else {
                    throw invalid(column)
                }
                return value
            }
            return Row(week: week, date: date, channel: fields[2], values: values)
        }
    }

    private static func validate(_ rows: [Row], week: Int) throws {
        guard rows.count == 3, Set(rows.map(\.channel)) == Set(["Search", "Social", "Video"]) else {
            throw ReportEngineError.invalidWeek(week, "expected exactly one row each for Search, Social, Video")
        }
        guard Set(rows.map(\.date)).count == 1 else {
            throw ReportEngineError.invalidWeek(week, "channel dates disagree")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard calendar.component(.weekday, from: rows[0].date) == 2 else {
            throw ReportEngineError.invalidWeek(week, "week_start must be a Monday")
        }
    }

    private static func figures(_ rows: [Row]) throws -> ReportFigures {
        if rows.isEmpty { return ReportFigures(Array(repeating: .unavailable, count: 6)) }
        func total(_ index: Int) throws -> ReportFigure {
            guard rows.allSatisfy({ $0.values[index] != nil }) else { return .missingInput }
            return .value(try rows.reduce(Decimal.zero) { try calculate($0, $1.values[index]!, .add) })
        }
        let impressions = try total(0), clicks = try total(1), spend = try total(2), leads = try total(3)
        let ctr: ReportFigure
        if let numerator = clicks.number, let denominator = impressions.number {
            ctr = denominator == 0 ? .unavailable : .value(try calculate(calculate(numerator, 100, .multiply), denominator, .divide))
        } else {
            ctr = .missingInput
        }
        let cpl: ReportFigure
        if spend == .missingInput {
            cpl = .missingAdSpend
        } else if let numerator = spend.number, let denominator = leads.number {
            cpl = denominator == 0 ? .noLeads : .value(try calculate(numerator, denominator, .divide))
        } else {
            cpl = .missingInput
        }
        return ReportFigures([impressions, clicks, ctr, spend, leads, cpl])
    }

    private static func change(_ now: ReportFigure, _ last: ReportFigure, adSpend: Bool) throws -> ReportFigure {
        guard let prior = last.number, prior != 0 else { return .unavailable }
        if adSpend && now == .missingInput { return .missingAdSpend }
        guard let current = now.number else { return now == .noLeads ? .unavailable : now }
        return .value(try calculate(calculate(calculate(current, prior, .subtract), 100, .multiply), prior, .divide))
    }

    private static func rateChange(_ now: ReportFigure, _ last: ReportFigure,
                                   _ numerator: ReportFigure, _ denominator: ReportFigure,
                                   _ priorNumerator: ReportFigure, _ priorDenominator: ReportFigure) throws -> ReportFigure {
        guard let prior = last.number, prior != 0 else { return .unavailable }
        guard now.number != nil else { return now == .noLeads ? .unavailable : now }
        guard let n = numerator.number, let d = denominator.number,
              let pn = priorNumerator.number, let pd = priorDenominator.number else {
            return .missingInput
        }
        let currentProduct = try calculate(n, pd, .multiply)
        let priorProduct = try calculate(pn, d, .multiply)
        return .value(try calculate(calculate(calculate(currentProduct, priorProduct, .subtract), 100, .multiply), priorProduct, .divide))
    }

    private enum Operation { case add, subtract, multiply, divide }

    private static func calculate(_ lhs: Decimal, _ rhs: Decimal, _ operation: Operation) throws -> Decimal {
        var a = lhs, b = rhs, result = Decimal.zero
        let error: Decimal.CalculationError
        switch operation {
        case .add: error = NSDecimalAdd(&result, &a, &b, .plain)
        case .subtract: error = NSDecimalSubtract(&result, &a, &b, .plain)
        case .multiply: error = NSDecimalMultiply(&result, &a, &b, .plain)
        case .divide: error = NSDecimalDivide(&result, &a, &b, .plain)
        }
        // Repeating quotients use Decimal's full precision, never display precision.
        guard error == .noError || (operation == .divide && error == .lossOfPrecision) else {
            throw ReportEngineError.arithmetic("\(operation): \(error)")
        }
        return result
    }

    private static func display(_ figure: ReportFigure, metric: Int, change: Bool = false) -> String {
        switch figure {
        case .missingInput: return "[missing: needs input]"
        case .missingAdSpend: return "[missing: depends on ad spend]"
        case .noLeads: return "n/a (no leads)"
        case .unavailable: return "n/a"
        case let .value(value):
            let places = change ? 1 : ([0, 1, 4].contains(metric) ? 0 : 2)
            var input = value, rounded = Decimal.zero
            NSDecimalRound(&rounded, &input, places, .plain)
            let negative = rounded < 0
            if negative { rounded.negate() }
            let raw = NSDecimalString(&rounded, Locale(identifier: "en_US_POSIX"))
            let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
            let digits = Array(parts[0])
            var whole = ""
            for index in digits.indices {
                if !change && index > 0 && (digits.count - index).isMultiple(of: 3) { whole += "," }
                whole.append(digits[index])
            }
            let fraction = parts.count > 1 ? String(parts[1]) : ""
            let fixed = whole + (places == 0 ? "" : "." + fraction + String(repeating: "0", count: max(0, places - fraction.count)))
            if change { return (negative ? "−" : "+") + fixed + "%" }
            return ([3, 5].contains(metric) ? "$" : "") + fixed + (metric == 2 ? "%" : "")
        }
    }

    /// CSV quoted fields, escaped quotes, CRLF/LF, and an optional UTF-8 BOM.
    private static func csvRecords(_ source: String) throws -> [[String]] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let characters = Array(normalized.hasPrefix("\u{FEFF}") ? String(normalized.dropFirst()) : normalized)
        var records: [[String]] = [], fields: [String] = [], field = ""
        var quoted = false, closedQuote = false, index = 0, recordStarted = false
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else { quoted = false; closedQuote = true }
                } else { field.append(character) }
            } else if character == "," || character == "\n" {
                fields.append(field)
                field = ""
                closedQuote = false
                if character == "\n" {
                    if recordStarted || fields.count > 1 { records.append(fields) }
                    fields = []
                    recordStarted = false
                } else { recordStarted = true }
            } else {
                guard !closedQuote else { throw ReportEngineError.invalidCSV("text after closing quote") }
                if character == "\"" {
                    guard field.isEmpty else { throw ReportEngineError.invalidCSV("quote inside unquoted field") }
                    quoted = true
                } else { field.append(character) }
                recordStarted = true
            }
            index += 1
        }
        guard !quoted else { throw ReportEngineError.invalidCSV("unterminated quoted field") }
        if recordStarted { fields.append(field); records.append(fields) }
        return records
    }
}
