# Choose a Report Format

Use a metric report to inspect the ten source measurements. Use a debt report to inspect ranked items and their evidence.

## Metric reports

`swift-debt analyze` supports `text`, `json`, `csv`, `html`, and `diagnostics`. JSON is the stable choice for automation because it contains structured metrics, diagnostics, source counts, and `complete`. HTML is self-contained. Diagnostic format puts file locations in a form that build logs can surface.

```sh
swift-debt analyze Sources --format json --output reports/metrics.json
```

---

## Ranked debt reports

`swift-debt debt analyze` supports `json`, `markdown`, `dot`, `text`, `compact`, and `debtmap-json`. `debt-dashboard` is available through the general `analyze` workflow. JSON contains ranked items, score breakdowns, aggregations, and missing evidence. DOT renders relationships for graph tools; it is not a score interchange format.

```sh
swift-debt debt analyze Sources --format json --output reports/debt.json
```

Use `--top`, `--head`, `--tail`, `--min-score`, `--min-priority`, `--category`, and `--level` to narrow ranked output. File aggregation is the default. `--aggregation none` keeps individual items without file groups.

---

## Treat the exit status as part of the result

Status `0` means a complete analysis passed enabled gates. Status `1` means a complete analysis violated an opted-in gate. Status `2` means input, configuration, or analysis was invalid or incomplete. A report file can still be written with a nonzero status, so automation must check the status and JSON `complete` field before using a report as a passing result.
