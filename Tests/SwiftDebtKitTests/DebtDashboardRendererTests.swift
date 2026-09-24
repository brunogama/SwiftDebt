import Foundation
import JavaScriptCore
import SwiftDebtCore
import SwiftDebtKit
import Testing

@testable import SwiftDebtReporting

@Suite("Debt dashboard rendering")
struct DebtDashboardRendererTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func deterministicFixtureReportRendersDashboardWithoutRunningAnalysis() throws {
        let fixtureData = try data("Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json")
        let report = try JSONDecoder().decode(DebtReport.self, from: fixtureData)
        let renderer = ReportRenderer()

        let dashboard = try renderer.renderDebtDashboard(from: fixtureData)
        let repeated = try renderer.renderDebtDashboard(report)
        let expected = try read("Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-dashboard.golden.html")

        #expect(dashboard == repeated)
        #expect(dashboard == expected)
        #expect(dashboard.contains("SwiftDebt debt dashboard"))
        #expect(dashboard.contains("swiftdebt-report"))
    }

    @Test func dashboardAssetsIncludeReportLoadingControlsAndRemainSelfContained() throws {
        let report: DebtReport = try loadJSON(
            "Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json")

        let dashboard = try ReportRenderer().renderDebtDashboard(report)

        #expect(dashboard.contains("<script id=\"swiftdebt-initial-report\" type=\"application/json\">"))
        #expect(dashboard.contains("id=\"report-input\""))
        #expect(dashboard.contains("id=\"comparison-input\""))
        #expect(dashboard.contains("id=\"priority-filter\""))
        #expect(dashboard.contains("id=\"category-filter\""))
        #expect(dashboard.contains("id=\"level-filter\""))
        #expect(dashboard.contains("FileReader"))
        #expect(dashboard.contains("Content-Security-Policy"))
        #expect(dashboard.contains("script-src 'unsafe-inline'"))
        let browserAsset = try #require(dashboard.components(separatedBy: "<script>\n").last)
        #expect(!browserAsset.contains("priorityThresholds"))
        #expect(!browserAsset.contains("problematicItemScoreThreshold"))
        #expect(!browserAsset.contains("totalConfiguredWeight"))
        #expect(!browserAsset.contains("totalAvailableWeight"))
        #expect(dashboard.contains("connect-src 'none'"))
        #expect(!dashboard.contains("https://"))
        #expect(!dashboard.contains("http://"))
        #expect(!dashboard.contains("<script src="))
        #expect(!dashboard.contains("<link rel=\"stylesheet\""))
    }

    @Test func selectedDashboardReportFilesValidateAndRender() throws {
        let fixturePath = "Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json"
        let report: DebtReport = try loadJSON(fixturePath)
        let fixtureJSON = try read(fixturePath)
        let selectedReportJSON = fixtureJSON.replacingOccurrences(
            of: "\"generator\" : \"SwiftDebt\"",
            with: "\"generator\" : \"LoadedFixture\""
        )
        let comparisonReportJSON = try read(
            "Tests/SwiftDebtKitTests/Fixtures/DebtImprovement/comparison.golden.json"
        )
        let dashboard = try ReportRenderer().renderDebtDashboard(report)
        let script = try dashboardApplicationScript(from: dashboard)
        let context = try makeDashboardScriptContext(initialReportJSON: fixtureJSON)

        context.evaluateScript(script)
        try context.assertNoException()
        #expect(try context.textContent(of: "report-title") == "SwiftDebt schema 2 - 2 ranked items")

        try context.selectFile(id: "report-input", name: "selected-report.json", content: selectedReportJSON)
        #expect(try context.textContent(of: "status") == "Loaded selected-report.json.")
        #expect(try context.textContent(of: "report-title") == "LoadedFixture schema 2 - 2 ranked items")
        #expect(try context.descendantText(of: "item-table").contains("App.Beta.run()"))

        try context.selectFile(id: "comparison-input", name: "comparison-report.json", content: comparisonReportJSON)
        #expect(try context.textContent(of: "status") == "Loaded comparison-report.json.")
        let comparisonText = try context.descendantText(of: "comparison")
        #expect(comparisonText.contains("App.New.feature()"))
        #expect(comparisonText.contains("App.Legacy.clean()"))
        #expect(comparisonText.contains("App.Service.run()"))
        #expect(comparisonText.contains("90 / critical"))
        #expect(comparisonText.contains("60 / medium"))
        #expect(comparisonText.contains("-30"))
        #expect(comparisonText.contains("Sources/App.swift"))
        #expect(comparisonText.contains("-5"))

        try context.selectFile(id: "comparison-input", name: "not-a-comparison.json", content: fixtureJSON)
        #expect(
            try context.textContent(of: "status")
                == "Expected SwiftDebt debt report comparison schema version 1"
        )
        #expect(try context.descendantText(of: "comparison") == comparisonText)

        try context.selectFile(id: "report-input", name: "invalid-report.json", content: "{}")
        #expect(try context.textContent(of: "status") == "Expected SwiftDebt debt report schema version 2")
        #expect(try context.textContent(of: "report-title") == "LoadedFixture schema 2 - 2 ranked items")
    }

    @Test func dashboardVisualizesDependencyEdgesRatherThanAggregationMembership() throws {
        let fixtureData = try data("Tests/SwiftDebtKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json")
        let graph = SwiftDependencyGraph(
            nodes: [
                SwiftGraphNode(
                    id: "App.Alpha.help()",
                    kind: .callable,
                    module: "App",
                    displayName: "Alpha.help()"
                ),
                SwiftGraphNode(
                    id: "App.Beta.run()",
                    kind: .callable,
                    module: "App",
                    displayName: "Beta.run()"
                ),
            ],
            edges: [
                SwiftGraphEdge(
                    source: "App.Beta.run()",
                    target: "App.Alpha.help()",
                    kind: .call,
                    confidence: .resolvedSyntax,
                    location: SourceLocation(file: "Sources/Beta.swift", line: 12, column: 15),
                    note: "Beta.run calls Alpha.help"
                )
            ],
            couplingRisks: [],
            dependencyContexts: [],
            statistics: CallGraphStatistics(
                nodeCount: 2,
                edgeCount: 1,
                resolvedEdgeCount: 1,
                ambiguousEdgeCount: 0,
                unresolvedEdgeCount: 0,
                syntaxOnlyNote: "Syntax-only graph."
            ),
            dot: ""
        )
        var reportObject = try #require(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        reportObject["dependencyGraph"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(graph))
        let reportData = try JSONSerialization.data(withJSONObject: reportObject, options: [.sortedKeys])

        let dashboard = try ReportRenderer().renderDebtDashboard(from: reportData)
        let script = try dashboardApplicationScript(from: dashboard)
        let context = try makeDashboardScriptContext(initialReportJSON: embeddedReportJSON(from: dashboard))

        context.evaluateScript(script)
        try context.assertNoException()
        let graphText = try context.descendantText(of: "graph")
        #expect(graphText.contains("Beta.run() -> Alpha.help() (call, resolvedSyntax)"))
        #expect(!graphText.contains("file:Sources ->"))
    }

    @Test func analysisServiceRendersDebtDashboardWhenFormatIsSelected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "final class Worker { func run(_ value: Int) { if value > 0 { print(value) } } }".write(
            to: directory.appendingPathComponent("Worker.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await AnalysisService().run(
            .init(
                path: directory.path,
                format: .debtDashboard,
                debtAnalysisOptions: DebtAnalysisOptions(aggregationStrategy: .none, top: 1),
                lcovPath: "missing.lcov"
            ))

        #expect(result.standardOutput.contains("SwiftDebt debt dashboard"))
        #expect(result.standardOutput.contains("swiftdebt-report"))
        #expect(result.standardOutput.contains("id=\"swiftdebt-initial-report\""))
        #expect(result.standardOutput.contains("\"dependencyGraph\""))
    }

    private func dashboardApplicationScript(from dashboard: String) throws -> String {
        let scriptStart = try #require(dashboard.range(of: "<script>\n", options: .backwards))
        let scriptBody = dashboard[scriptStart.upperBound...]
        let scriptEnd = try #require(scriptBody.range(of: "\n</script>"))

        return String(scriptBody[..<scriptEnd.lowerBound])
    }

    private func embeddedReportJSON(from dashboard: String) throws -> String {
        let marker = "<script id=\"swiftdebt-initial-report\" type=\"application/json\">\n"
        let reportStart = try #require(dashboard.range(of: marker))
        let reportBody = dashboard[reportStart.upperBound...]
        let reportEnd = try #require(reportBody.range(of: "\n</script>"))

        return String(reportBody[..<reportEnd.lowerBound])
    }

    private func makeDashboardScriptContext(initialReportJSON: String) throws -> DashboardScriptContext {
        let context = DashboardScriptContext()
        try context.evaluateHarness(initialReportJSON: initialReportJSON)

        return context
    }

    private func loadJSON<T: Decodable>(_ path: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(path))
    }

    private func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}

private final class DashboardScriptContext {
    private let context = JSContext()
    private var exceptionMessage: String?

    init() {
        context?.exceptionHandler = { [weak self] _, exception in
            self?.exceptionMessage = exception?.toString()
        }
    }

    func evaluateHarness(initialReportJSON: String) throws {
        evaluateScript(
            """
            (()=>{class E{constructor(n){Object.assign(this,{name:n,id:"",tagName:n,children:[],listeners:{},className:"",textContent:"",value:"",files:[],firstChild:null,_innerHTML:""})}append(...n){this.children.push(...n);this.firstChild=this.children[0]||null}replaceChildren(...n){this.children=[];this.append(...n)}addEventListener(t,h){(this.listeners[t]||(this.listeners[t]=[])).push(h)}dispatchEvent(t){(this.listeners[t]||[]).forEach(h=>h({target:this,preventDefault(){}}))}focus(){document.activeElement=this}set innerHTML(v){this._innerHTML=v;this.children=[];this.firstChild=null}get innerHTML(){return this._innerHTML}}
            const ids="swiftdebt-initial-report report-input comparison-input priority-filter category-filter level-filter query-filter status report-title summary item-table drilldown graph comparison".split(" "),m=new Map(ids.map(id=>{const e=new E(id);e.id=id;return[id,e]}));
            m.get("swiftdebt-initial-report").textContent=\(try javaScriptStringLiteral(initialReportJSON));
            const dl={};globalThis.document={activeElement:null,getElementById:id=>m.get(id)||null,createElement:n=>new E(n),addEventListener(t,h){(dl[t]||(dl[t]=[])).push(h)}};
            globalThis.FileReader=class{readAsText(f){this.result=f.content;if(f.readError){this.onerror();return}this.onload()}};
            globalThis.dashboardHarness={selectFile(id,name,content){const i=m.get(id);i.files=[{name,content}];i.dispatchEvent("change")},textContent:id=>m.get(id).textContent,descendantText(id){function c(n){return[n.textContent||"",...n.children.flatMap(c)].join("|")}return c(m.get(id))}};
            })();
            """)
        try assertNoException()
    }

    func evaluateScript(_ script: String) {
        exceptionMessage = nil
        context?.evaluateScript(script)
    }

    func selectFile(id: String, name: String, content: String) throws {
        _ = try callHarness("selectFile", arguments: [id, name, content])
    }

    func textContent(of id: String) throws -> String {
        try callHarness("textContent", arguments: [id]).toString()
    }

    func descendantText(of id: String) throws -> String {
        try callHarness("descendantText", arguments: [id]).toString()
    }

    func assertNoException() throws {
        if let exceptionMessage {
            throw DashboardScriptError.javaScriptException(exceptionMessage)
        }
    }

    private func callHarness(_ name: String, arguments: [Any]) throws -> JSValue {
        exceptionMessage = nil
        let harness = try #require(context?.objectForKeyedSubscript("dashboardHarness"))
        let function = try #require(harness.objectForKeyedSubscript(name))
        let value = try #require(function.call(withArguments: arguments))
        try assertNoException()

        return value
    }

    private func javaScriptStringLiteral(_ value: String) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

private enum DashboardScriptError: Error {
    case javaScriptException(String)
}
