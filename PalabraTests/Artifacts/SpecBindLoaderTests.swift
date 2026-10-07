import XCTest
@testable import Palabra

final class SpecBindLoaderTests: XCTestCase {
    private let session = ArtifactSession(artifactID: nil, dryRun: false)

    private func registry(returning result: JSONValue, name: String = "library.words") -> CapabilityRegistry {
        CapabilityRegistry([makeCapability(name, .read, result: result)])
    }

    private func object(_ pairs: [String: JSONValue]) -> JSONValue { .object(pairs) }

    private func bindTable(_ columns: [SpecColumn], capability: String = "library.words") -> SpecTable {
        SpecTable(columns: columns, rows: nil, bind: SpecBind(capability: capability))
    }

    func testInlineTablePassesThrough() async {
        let table = SpecTable(columns: [SpecColumn(title: "Day", field: nil)], rows: [["Lunes"], ["Martes"]], bind: nil)
        let result = await SpecBindLoader.table(table, registry: CapabilityRegistry([]), session: session, granted: [])
        XCTAssertEqual(result, .loaded(ResolvedTable(columns: ["Day"], rows: [["Lunes"], ["Martes"]])))
    }

    func testBoundTableMapsFields() async {
        let items: JSONValue = .array([object(["spanish": .string("hola"), "translation": .string("hello")])])
        let table = bindTable([SpecColumn(title: "Word", field: "spanish"), SpecColumn(title: "Meaning", field: "translation")])
        let result = await SpecBindLoader.table(table, registry: registry(returning: items), session: session, granted: ["library.words"])
        XCTAssertEqual(result, .loaded(ResolvedTable(columns: ["Word", "Meaning"], rows: [["hola", "hello"]])))
    }

    func testColumnWithoutFieldUsesTitle() async {
        let items: JSONValue = .array([object(["spanish": .string("hola")])])
        let table = bindTable([SpecColumn(title: "spanish", field: nil)])
        let result = await SpecBindLoader.table(table, registry: registry(returning: items), session: session, granted: ["library.words"])
        XCTAssertEqual(result, .loaded(ResolvedTable(columns: ["spanish"], rows: [["hola"]])))
    }

    func testStringification() async {
        let items: JSONValue = .array([object([
            "a": .number(3), "b": .number(2.5), "c": .array([.string("a"), .string("b")]), "d": .null, "e": .bool(true),
        ])])
        let columns = ["a", "b", "c", "d", "e", "missing"].map { SpecColumn(title: $0, field: nil) }
        let result = await SpecBindLoader.table(bindTable(columns), registry: registry(returning: items), session: session, granted: ["library.words"])
        XCTAssertEqual(result, .loaded(ResolvedTable(columns: ["a", "b", "c", "d", "e", "missing"], rows: [["3", "2.5", "a, b", "", "true", ""]])))
    }

    func testBoundChartMapsLabelAndValue() async {
        let items: JSONValue = .array([
            object(["day": .string("2026-10-05"), "count": .number(2)]),
            object(["day": .string("2026-10-06"), "count": .string("5")]),
            object(["day": .string("2026-10-07"), "count": .string("n/a")]), // unparseable value: skipped
        ])
        let chart = SpecChart(style: .line, title: nil, labels: nil, series: nil, bind: SpecBind(capability: "stats.wordsPerDay"), labelField: "day", valueField: "count")
        let result = await SpecBindLoader.chart(chart, registry: registry(returning: items, name: "stats.wordsPerDay"), session: session, granted: ["stats.wordsPerDay"])
        XCTAssertEqual(result, .loaded(ResolvedChart(labels: ["2026-10-05", "2026-10-06"], series: [ResolvedChartSeries(name: nil, values: [2, 5])])))
    }

    func testInlineChartPassesThrough() async {
        let chart = SpecChart(style: .bar, title: "T", labels: ["a", "b"], series: [SpecChartSeries(name: "S", values: [1, 2])], bind: nil, labelField: nil, valueField: nil)
        let result = await SpecBindLoader.chart(chart, registry: CapabilityRegistry([]), session: session, granted: [])
        XCTAssertEqual(result, .loaded(ResolvedChart(labels: ["a", "b"], series: [ResolvedChartSeries(name: "S", values: [1, 2])])))
    }

    func testRowCapAt200() async {
        let items: JSONValue = .array((0..<300).map { object(["n": .number(Double($0))]) })
        let result = await SpecBindLoader.table(bindTable([SpecColumn(title: "n", field: nil)]), registry: registry(returning: items), session: session, granted: ["library.words"])
        guard case .loaded(let table) = result else { return XCTFail("expected loaded") }
        XCTAssertEqual(table.rows.count, 200)
        XCTAssertEqual(table.rows.last, ["199"])
    }

    func testChartPointCapAt500() async {
        let items: JSONValue = .array((0..<700).map { object(["l": .string("x"), "v": .number(Double($0))]) })
        let chart = SpecChart(style: .bar, title: nil, labels: nil, series: nil, bind: SpecBind(capability: "library.words"), labelField: "l", valueField: "v")
        let result = await SpecBindLoader.chart(chart, registry: registry(returning: items), session: session, granted: ["library.words"])
        guard case .loaded(let resolved) = result else { return XCTFail("expected loaded") }
        XCTAssertEqual(resolved.values.count, 500)
        XCTAssertEqual(resolved.labels.count, 500)
    }

    func testEmptyResultIsLoadedEmpty() async {
        let result = await SpecBindLoader.table(bindTable([SpecColumn(title: "Word", field: "spanish")]), registry: registry(returning: .array([])), session: session, granted: ["library.words"])
        XCTAssertEqual(result, .loaded(ResolvedTable(columns: ["Word"], rows: [])))
    }

    func testUngrantedBindFails() async {
        let result = await SpecBindLoader.table(bindTable([SpecColumn(title: "Word", field: "spanish")]), registry: registry(returning: .array([])), session: session, granted: [])
        XCTAssertEqual(result, .failed("Couldn't load data"))
    }

    func testUnknownCapabilityFails() async {
        let result = await SpecBindLoader.table(bindTable([SpecColumn(title: "x", field: nil)], capability: "nope"), registry: CapabilityRegistry([]), session: session, granted: ["nope"])
        XCTAssertEqual(result, .failed("Couldn't load data"))
    }

    func testNonArrayResultFails() async {
        let result = await SpecBindLoader.table(bindTable([SpecColumn(title: "x", field: nil)]), registry: registry(returning: object(["a": .number(1)])), session: session, granted: ["library.words"])
        XCTAssertEqual(result, .failed("Couldn't load data"))
    }
}
