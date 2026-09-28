# Build the documentation

The `SwiftDebtKit.docc` catalog owns the tutorials and articles. Swift-DocC generates the API reference from public symbol graphs for `SwiftDebtKit`, `SwiftDebtCore`, and `SwiftDebtInteractive`. The other source targets declare no public APIs. Swift Package Index builds the same catalog and symbols from tagged releases.

## Build locally

Install Swift 6.2 and Python 3. Run:

```sh
python3 scripts/build_documentation.py --output .build/SwiftDebt
python3 -m http.server 8000 --directory .build
```

Open `http://localhost:8000/SwiftDebt/documentation/swiftdebtkit/`. The build creates a static DocC site at `.build/SwiftDebt/`, with references for the other public modules under `api/swiftdebtcore/` and `api/swiftdebtinteractive/`. Pass a new or empty output directory for each build. If you use another hosting path, pass it with `--hosting-base-path`.

---

## Edit source content

Write tutorials in `Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/` and articles in `Sources/SwiftDebtKit/SwiftDebtKit.docc/Articles/`. Add each page to the topics in `SwiftDebtKit.md`. Use `<doc:PageName>` for links to another article in the catalog. DocC checks those links during the build.

`Package.swift` declares the catalog as a `SwiftDebtKit` resource so SwiftPM and Swift Package Index discover it during DocC generation. Removing that declaration leaves symbol pages but drops the articles from the DocC archive.

The build requests public symbols and treats DocC warnings as errors. It also verifies that every tutorial and article appears in the generated `SwiftDebtKit` archive.

---

## Publish

The documentation workflow builds DocC on pull requests. The release workflow publishes the static site and all three API references to GitHub Pages after main passes release checks. `.spi.yml` asks Swift Package Index to build DocC for the same three targets. Swift Package Index hosting starts after the repository is accepted into its package list and a tagged revision containing these files is indexed.
