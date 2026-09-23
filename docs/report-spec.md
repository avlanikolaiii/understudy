# Weekly client update: report spec (v0.1, proposed)

This is the definition the numerical tests are scored against. It's a proposal until it's approved, and changing it later means re-scoring every test.

## Source data

One Google Sheet per client. In the prototype fixtures it's one CSV per snapshot. One row per channel per week:

| Column | Type | Example | Notes |
|---|---|---|---|
| `week` | integer | `4` | ISO week number within the campaign, starting at 0 |
| `week_start` | date `YYYY-MM-DD` | `2026-08-31` | Monday of that week |
| `channel` | text | `Search` | One of `Search`, `Social`, `Video` |
| `impressions` | integer | `48210` | |
| `clicks` | integer | `1377` | |
| `spend_usd` | decimal | `1843.27` | May be blank. See "Missing data" |
| `leads` | integer | `96` | |

**Source figures** are these column values as written in the sheet. Totals are sums across channels for one week.

## Report figures

All calculations use the **unrounded** source values. Rounding happens once, at display time.

| Figure | Formula | Display | Rounding |
|---|---|---|---|
| Impressions | Σ impressions | `48,210` | integer, thousands separator |
| Clicks | Σ clicks | `1,377` | integer, thousands separator |
| CTR | Σ clicks ÷ Σ impressions × 100 | `2.86%` | 2 decimals, half-up |
| Ad spend | Σ spend_usd | `$5,120.40` | 2 decimals, half-up, thousands separator |
| Leads | Σ leads | `351` | integer |
| Cost per lead | Σ spend_usd ÷ Σ leads | `$14.59` | 2 decimals, half-up. `n/a (no leads)` if Σ leads = 0 |
| Change vs last week | (this − last) ÷ last × 100 | `+4.7%` / `−2.1%` | 1 decimal, half-up, always signed. `n/a` if last = 0 or last is missing |

"Half-up" means decimal half-up (`ROUND_HALF_UP`), not banker's rounding and not binary-float rounding. Implementations must use decimal arithmetic.

## Missing data

A required source figure is **missing** when its cell is blank. Zero is not missing.

- Every figure that depends on a missing value is shown as `[missing: needs input]`. That includes totals: one blank channel makes the week's total spend missing, not a partial sum.
- Figures calculated from it (cost per lead, spend change) are shown as `[missing: depends on ad spend]`.
- The report title gets the suffix ` (DRAFT, incomplete)`.
- A short `## Missing data` section at the top names each missing cell by channel and column.
- No value is ever estimated, carried forward, or invented.

## Template sections

See `templates/weekly-update.md`. The four sections and their scoring:

| Section | Scored how |
|---|---|
| Title and dates | Exact match |
| Numbers table | Exact match, per the rules above |
| Summary, Highlight, Next week | Human judgment: acceptable or not. Reference text in the expected reports is an example, not the answer |
