# Configure an Analysis

Put `.swift-debt.json` at the analysis root to share policy between local commands and CI. The CLI accepts `--config PATH` when the file lives elsewhere. The build plugin requires the root file to exist; `{}` is valid.

## Start with an explicit policy

```json
{
  "typeScope": "nominals",
  "scoring": "none",
  "thresholds": { "CCF": 15, "NOPF": 6 },
  "exclude": ["Generated", "Vendor"],
  "jobs": 4,
  "failOnViolation": true,
  "strictSyntax": false
}
```

`classes` is the default type scope. `nominals` also measures structs, enums, and actors. The five paper-defined metric thresholds are defaults; the example values above are project policy. A metric above its threshold produces a finding. `failOnViolation` changes a completed analysis with findings from exit status `0` to `1`.

---

## Control source and parser limits

`exclude` contains literal root-relative path prefixes, not glob patterns. `jobs` accepts 1 through 64. `maximumFileBytes` defaults to 16 MiB per source file. `minimumDuplicateLines` defaults to 11, and `maximumDuplicateComparisons` bounds the duplicate-matching work. Reaching that comparison budget fails the analysis instead of reporting no clones.

By default, a source file with a parse error is skipped with a warning. Set `strictSyntax` to make the report incomplete and withhold scores when a parse error occurs.

---

## Configure ranked evidence

Set `debtReferenceTime` to an ISO-8601 timestamp such as `2026-09-12T00:00:00Z` when Git-history recency is needed. Use `lcovPath` for LCOV coverage evidence. A relative LCOV path is resolved from the analysis root. `debtAnalysis` configures ranking and filters; `debtValidation` sets a maximum ranked score.

CLI scalar options override matching file settings. CLI thresholds merge by metric, while exclusions append. `--fail-on-violation` and `--strict` can enable their policies but cannot disable values already enabled in the file. Unknown JSON keys and metric IDs fail configuration loading.
