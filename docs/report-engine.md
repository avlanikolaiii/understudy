# Weekly report engine

`apps/mac/Sources/Understudy/ReportEngine.swift` computes real figures from supplied CSV
and renders the layout in `templates/weekly-update.md`, following
`docs/report-spec.md`. It is a pure Foundation module: no file access, network,
Supabase, SwiftUI, or shared mutable state. The teaching source data is fictional;
the arithmetic and Markdown generation are implemented.

## App API

```swift
let report = try ReportEngine.report(
    csv: csvText,
    week: 3,
    client: "Norte Studio",
    agency: "Faro Creative"
)
// report.markdown
// report.isComplete
// report.missingCells: [ReportMissingCell] (week, channel, column)
// report.thisWeek.adSpend.number: Decimal?
// report.lastWeek.costPerLead
// report.changes.ctr.number: Decimal? (percent, not fractional change)
```

The `agency` argument defaults to the teaching fixture's `Faro Creative`. Real
callers should pass their agency. The API throws `ReportEngineError` for malformed
CSV, invalid cells or week structure, and unsupported decimal arithmetic.

`WeeklyReport`, `ReportFigures`, `ReportFigure`, and `ReportMissingCell` are
`Sendable`. Results are immutable. Both weekly figures and changes expose
`impressions`, `clicks`, `ctr`, `adSpend`, `leads`, and `costPerLead`.
`ReportFigure` distinguishes `.value(Decimal)`, `.missingInput`,
`.missingAdSpend`, `.noLeads`, and `.unavailable`; `.number` is nil for every
non-numeric state. Consumers should use these states rather than parse Markdown.

**`isComplete` describes source-data completeness, not readiness to send.**
Summary, Highlight, and Next week each contain exactly
`[AI step: not connected yet]`. There is no generated judgment prose. App wiring,
file export/read-back evidence, receipts, tracker/email behavior, and the AI proxy
are separate integration work.

## Calculation and missing-data behavior

- Parse directly into `Decimal`, never `Double`. Sum source values before any
  display rounding. Raw numeric results retain Decimal's full precision.
- Display uses decimal half-up, including negative change ties, fixed decimal
  places, English thousands separators, and the spec's Unicode minus sign.
  CTR and CPL changes use cross-products of source totals so subtracting repeating
  quotients cannot move an exact rounding tie. Repeating divisions retain full
  Decimal precision; overflow, underflow, and lossy sums/products throw.
- One blank numeric cell invalidates its total. Missing spend makes both CPL and
  its dependent changes missing. There are no partial sums or carried values.
- Missing cells in either displayed week get a draft suffix and a top-of-report
  list identifying week, channel, and column. Cells in other weeks are not included.
- An absent previous week displays `n/a` for its figures and all changes, and does
  not by itself mark the current report incomplete. A missing or zero previous
  figure always makes its change `n/a`, including when this week's figure is also
  missing. This follows the spec's prior-value rule.
- Zero leads produces `n/a (no leads)` for CPL when spend is present. Missing spend
  takes precedence over zero leads. Zero impressions produces `n/a` for CTR;
  the spec does not prescribe a separate zero-impressions label.
- Dates use the Gregorian calendar, UTC, and fixed English formatting. Week end is
  six days after `week_start`. Output does not depend on the machine's locale,
  time zone, current date, or CSV row order.

## Input validation

The header must contain the seven spec columns in their documented order. Quoted
fields, escaped quotes, LF/CRLF, a UTF-8 BOM, and an omitted final newline are
supported. Empty cells are missing; zeroes remain values. Invalid numeric text is
an error, not a missing value. Counts must be nonnegative integers and spend a
nonnegative plain decimal, without currency symbols, separators, or exponents.
Inputs Decimal would silently truncate are rejected.

Each displayed week that exists must contain exactly one row for Search, Social,
and Video, with matching Monday dates. An absent channel or duplicate row throws
instead of creating a misleading total. If the previous week exists, its start
must be seven days earlier. All input rows receive cell validation; week-level
structure validation applies to the requested week and its comparison week.

## Verified checks

Run from the repository root using Command Line Tools:

```sh
swiftc -module-cache-path /private/tmp/understudy-mc apps/mac/Sources/Understudy/ReportEngine.swift apps/mac/Tests/ReportChecks.swift -o /tmp/understudy-report-checks && /tmp/understudy-report-checks
```

The checks compare the title, date line, and every table line exactly with teaching
reports 1, 2, and 3. They also cover synthetic positive/negative half-up ties,
unrounded source and rate calculations, missing Video spend, other blank numeric
cells, zero spend/leads/denominators, absent and missing comparison values, CSV
normalization, row order, and malformed-input rejection. Synthetic cases are built
inside the test. Only the explicitly named teaching CSV and three teaching reports
are read. No held-out data was accessed. No spec/teaching-fixture disagreement was
found.

The standalone engine checks passed, including compilation with Swift 6,
`-strict-concurrency=complete`, and `-warnings-as-errors`. App integration and end-to-end account,
connector, export, and receipt flows have not been tested by these checks.
