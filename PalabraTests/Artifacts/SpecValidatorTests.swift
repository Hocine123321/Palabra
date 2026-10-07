import XCTest
@testable import Palabra

final class SpecValidatorTests: XCTestCase {
    private let registry = CapabilityRegistry([
        makeCapability("library.words", .read),
        makeCapability("stats.wordsPerDay", .read),
        makeCapability("review.flag", .write),
        makeCapability("storage.get", .local),
    ])

    private let everyBlockJSON = """
    {"blocks":[
    {"type":"heading","level":2,"text":"H"},
    {"type":"text","text":"T"},
    {"type":"list","ordered":true,"items":["a","b"]},
    {"type":"table","columns":[{"title":"Day"}],"rows":[["Lunes"]]},
    {"type":"chart","style":"line","title":"C","labels":["a"],"series":[{"name":"S","values":[1]}]},
    {"type":"stats","tiles":[{"label":"Words","value":"42"}]},
    {"type":"checklist","id":"c1","items":["x"]},
    {"type":"roadmap","id":"r1","steps":[{"title":"s","detail":"d"}]},
    {"type":"columns","children":[{"type":"text","text":"in col"}]},
    {"type":"section","title":"Sec","children":[{"type":"text","text":"in sec"}]}
    ]}
    """

    private func decoded(_ json: String, file: StaticString = #filePath, line: UInt = #line) -> ArtifactSpec {
        guard case .success(let spec) = SpecValidator.decode(json) else {
            XCTFail("decode failed", file: file, line: line)
            return ArtifactSpec(blocks: [])
        }
        return spec
    }

    private func validated(_ blocks: [SpecBlock], requests: [String] = [], file: StaticString = #filePath, line: UInt = #line) -> ValidatedSpec? {
        guard case .success(let value) = SpecValidator.validate(ArtifactSpec(blocks: blocks), requests: requests, registry: registry) else {
            XCTFail("validate failed", file: file, line: line)
            return nil
        }
        return value
    }

    private func chars(_ count: Int) -> String { String(repeating: "a", count: count) }

    // MARK: decode

    func testDecodesEveryBlockType() {
        let spec = decoded(everyBlockJSON)
        XCTAssertEqual(spec.blocks.count, 10)
        XCTAssertEqual(spec.blocks[0], .heading(level: 2, text: "H"))
        XCTAssertEqual(spec.blocks[2], .list(ordered: true, items: ["a", "b"]))
        XCTAssertEqual(spec.blocks[3], .table(SpecTable(columns: [SpecColumn(title: "Day", field: nil)], rows: [["Lunes"]], bind: nil)))
        XCTAssertEqual(spec.blocks[6], .checklist(id: "c1", items: ["x"]))
        XCTAssertEqual(spec.blocks[9], .section(title: "Sec", children: [.text("in sec")]))
    }

    func testEncodeDecodeRoundTrip() throws {
        let spec = decoded(everyBlockJSON)
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(ArtifactSpec.self, from: data), spec)
    }

    func testUnknownBlockTypeIsDropped() {
        let spec = decoded(#"{"blocks":[{"type":"hologram"},{"type":"text","text":"ok"}]}"#)
        XCTAssertEqual(spec.blocks, [.text("ok")])
    }

    func testBlockMissingRequiredFieldIsDropped() {
        let spec = decoded(#"{"blocks":[{"type":"table"},{"type":"text","text":"ok"}]}"#)
        XCTAssertEqual(spec.blocks, [.text("ok")])
    }

    func testNestedUnknownChildDropped() {
        let spec = decoded(#"{"blocks":[{"type":"section","title":"S","children":[{"type":"nope"},{"type":"text","text":"kept"}]}]}"#)
        XCTAssertEqual(spec.blocks, [.section(title: "S", children: [.text("kept")])])
    }

    func testCellsAndTilesAcceptNumbersAndBools() {
        let spec = decoded(#"{"blocks":[{"type":"table","columns":[{"title":"A"}],"rows":[[1],[2.5],[true],[null]]},{"type":"stats","tiles":[{"label":"Words","value":42}]}]}"#)
        XCTAssertEqual(spec.blocks[0], .table(SpecTable(columns: [SpecColumn(title: "A", field: nil)], rows: [["1"], ["2.5"], ["true"], [""]], bind: nil)))
        XCTAssertEqual(spec.blocks[1], .stats([SpecStatTile(label: "Words", value: "42")]))
    }

    func testFencedPayloadDecodes() {
        let spec = decoded("```json\n" + #"{"blocks":[{"type":"text","text":"hi"}]}"# + "\n```")
        XCTAssertEqual(spec.blocks, [.text("hi")])
    }

    func testMalformedJSON() {
        XCTAssertEqual(SpecValidator.decode("{nope"), .failure(.malformed("the payload is not valid JSON with a \"blocks\" array")))
    }

    func testMissingBlocksKeyIsMalformed() {
        guard case .failure(.malformed) = SpecValidator.decode("{}") else { return XCTFail("expected malformed") }
    }

    // MARK: validate: shape caps

    func testAllBlocksUnknownIsEmpty() {
        let spec = decoded(#"{"blocks":[{"type":"hologram"},{"type":"also nope"}]}"#)
        XCTAssertEqual(SpecValidator.validate(spec, requests: [], registry: registry), .failure(.empty))
    }

    func testEmptyBlocksArrayIsEmpty() {
        XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: []), requests: [], registry: registry), .failure(.empty))
    }

    func testBlockCountCappedAt60() {
        let result = validated((0..<61).map { .text("t\($0)") })
        XCTAssertEqual(result?.spec.blocks.count, 60)
        XCTAssertEqual(result?.spec.blocks.last, .text("t59"))
    }

    func testDepthCappedAt4() {
        // S1{T1, S2{T2, S3{T3, S4{T4, S5{T5}}}}}: T3 sits at depth 4, S4's children would be depth 5.
        func chain(_ level: Int) -> SpecBlock {
            var children: [SpecBlock] = [.text("T\(level)")]
            if level < 5 { children.append(chain(level + 1)) }
            return .section(title: "S\(level)", children: children)
        }
        let result = validated([chain(1)])
        func depth(_ block: SpecBlock) -> Int {
            switch block {
            case .section(_, let children), .columns(let children): return 1 + (children.map(depth).max() ?? 0)
            default: return 1
            }
        }
        func texts(_ block: SpecBlock) -> [String] {
            switch block {
            case .text(let value): return [value]
            case .section(_, let children), .columns(let children): return children.flatMap(texts)
            default: return []
            }
        }
        let blocks = result?.spec.blocks ?? []
        XCTAssertEqual(blocks.map(depth).max(), 4)
        let all = blocks.flatMap(texts)
        XCTAssertTrue(all.contains("T3"))
        XCTAssertFalse(all.contains("T4"))
        XCTAssertFalse(all.contains("T5"))
    }

    func testEmptyContainersAreDropped() {
        let result = validated([.section(title: "Empty", children: [.text("   ")]), .columns([]), .text("kept")])
        XCTAssertEqual(result?.spec.blocks, [.text("kept")])
    }

    func testTableCappedAt20x200() {
        let columns = (0..<25).map { SpecColumn(title: "c\($0)", field: nil) }
        let rows = (0..<250).map { _ in (0..<25).map { "v\($0)" } }
        let block = validated([.table(SpecTable(columns: columns, rows: rows, bind: nil))])?.spec.blocks.first
        guard case .table(let table)? = block else { return XCTFail("expected a table") }
        XCTAssertEqual(table.columns.count, 20)
        XCTAssertEqual(table.rows?.count, 200)
        XCTAssertTrue(table.rows?.allSatisfy { $0.count == 20 } ?? false)
    }

    func testTableRowsArePaddedAndTrimmedToColumnCount() {
        let columns = [SpecColumn(title: "A", field: nil), SpecColumn(title: "B", field: nil)]
        let block = validated([.table(SpecTable(columns: columns, rows: [["1"], ["1", "2", "3"]], bind: nil))])?.spec.blocks.first
        guard case .table(let table)? = block else { return XCTFail("expected a table") }
        XCTAssertEqual(table.rows, [["1", ""], ["1", "2"]])
    }

    func testTableWithoutColumnsIsDropped() {
        XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: [.table(SpecTable(columns: [], rows: [], bind: nil))]), requests: [], registry: registry), .failure(.empty))
    }

    func testChartCappedAt500PointsAndLabelsAlignedToSeries() {
        let series = SpecChartSeries(name: "S", values: (0..<600).map(Double.init))
        let chart = SpecChart(style: .line, title: nil, labels: ["only", "two"], series: [series], bind: nil, labelField: nil, valueField: nil)
        guard case .chart(let result)? = validated([.chart(chart)])?.spec.blocks.first else { return XCTFail("expected a chart") }
        XCTAssertEqual(result.series?.first?.values.count, 500)
        XCTAssertEqual(result.labels?.count, 500)
        XCTAssertEqual(result.labels?.prefix(3).map { $0 }, ["only", "two", "3"])
    }

    func testChartWithoutDataSourceIsDropped() {
        let empty = SpecChart(style: .bar, title: "x", labels: [], series: [], bind: nil, labelField: nil, valueField: nil)
        XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: [.chart(empty)]), requests: [], registry: registry), .failure(.empty))
    }

    func testBoundChartNeedsBothFields() {
        let bind = SpecBind(capability: "stats.wordsPerDay", args: .object(["days": .number(7)]))
        let missing = SpecChart(style: .line, title: nil, labels: nil, series: nil, bind: bind, labelField: "day", valueField: nil)
        XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: [.chart(missing)]), requests: [], registry: registry), .failure(.empty))
        let ok = SpecChart(style: .line, title: nil, labels: nil, series: nil, bind: bind, labelField: "day", valueField: "count")
        let result = validated([.chart(ok)])
        XCTAssertEqual(result?.spec.blocks, [.chart(ok)])
        XCTAssertEqual(result?.requests, ["stats.wordsPerDay"])
    }

    func testHeadingLevelClampedAndEmptyTextDropped() {
        let result = validated([.heading(level: 0, text: "a"), .heading(level: 9, text: "b"), .heading(level: 2, text: "  "), .text("")])
        XCTAssertEqual(result?.spec.blocks, [.heading(level: 1, text: "a"), .heading(level: 3, text: "b")])
    }

    func testStatTilesCappedAndEmptyTilesDropped() {
        let tiles = (0..<20).map { SpecStatTile(label: "L\($0)", value: "\($0)") } + [SpecStatTile(label: "", value: "")]
        guard case .stats(let kept)? = validated([.stats(tiles)])?.spec.blocks.first else { return XCTFail("expected stats") }
        XCTAssertEqual(kept.count, 12)
    }

    // MARK: validate: string caps

    func testStringCaps() {
        let step = SpecRoadmapStep(title: chars(121), detail: chars(301))
        let columns = [SpecColumn(title: "A", field: nil)]
        let chart = SpecChart(style: .bar, title: chars(81), labels: [chars(41)], series: [SpecChartSeries(name: nil, values: [1])], bind: nil, labelField: nil, valueField: nil)
        let blocks: [SpecBlock] = [
            .heading(level: 1, text: chars(121)),
            .text(chars(2001)),
            .list(ordered: false, items: [chars(301)]),
            .table(SpecTable(columns: columns, rows: [[chars(201)]], bind: nil)),
            .chart(chart),
            .stats([SpecStatTile(label: chars(41), value: chars(61))]),
            .checklist(id: "c", items: [chars(201)]),
            .roadmap(id: "r", steps: [step]),
            .section(title: chars(121), children: [.text("x")]),
        ]
        let out = validated(blocks)?.spec.blocks ?? []
        XCTAssertEqual(out.count, 9)
        XCTAssertEqual(out[0], .heading(level: 1, text: chars(120)))
        XCTAssertEqual(out[1], .text(chars(2000)))
        XCTAssertEqual(out[2], .list(ordered: false, items: [chars(300)]))
        guard case .table(let table) = out[3], case .chart(let resultChart) = out[4], case .stats(let tiles) = out[5],
              case .checklist(_, let items) = out[6], case .roadmap(_, let steps) = out[7], case .section(let title, _) = out[8] else {
            return XCTFail("block kinds changed")
        }
        XCTAssertEqual(table.rows, [[chars(200)]])
        XCTAssertEqual(resultChart.title, chars(80))
        XCTAssertEqual(resultChart.labels, [chars(40)])
        XCTAssertEqual(tiles, [SpecStatTile(label: chars(40), value: chars(60))])
        XCTAssertEqual(items, [chars(200)])
        XCTAssertEqual(steps, [SpecRoadmapStep(title: chars(120), detail: chars(300))])
        XCTAssertEqual(title, chars(120))
    }

    func testListAndChecklistItemCounts() {
        let many = (0..<150).map { "i\($0)" }
        guard case .list(_, let listItems)? = validated([.list(ordered: false, items: many)])?.spec.blocks.first,
              case .checklist(_, let checkItems)? = validated([.checklist(id: "c", items: many)])?.spec.blocks.first else {
            return XCTFail("expected a list and a checklist")
        }
        XCTAssertEqual(listItems.count, 100)
        XCTAssertEqual(checkItems.count, 50)
    }

    // MARK: validate: binds and requests

    func testBindToWriteCapabilityDropsBlock() {
        let bind = SpecBind(capability: "review.flag", args: .object([:]))
        let table = SpecTable(columns: [SpecColumn(title: "A", field: "a")], rows: nil, bind: bind)
        XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: [.table(table)]), requests: [], registry: registry), .failure(.empty))
    }

    func testBindToUnknownOrLocalCapabilityDropsBlock() {
        for name in ["nope.nothing", "storage.get"] {
            let table = SpecTable(columns: [SpecColumn(title: "A", field: "a")], rows: nil, bind: SpecBind(capability: name))
            XCTAssertEqual(SpecValidator.validate(ArtifactSpec(blocks: [.table(table)]), requests: [], registry: registry), .failure(.empty), name)
        }
    }

    func testBindClearsInlineRowsAndKeepsArgs() {
        let bind = SpecBind(capability: "library.words", args: .object(["limit": .number(10)]))
        let table = SpecTable(columns: [SpecColumn(title: "Word", field: "spanish")], rows: [["ignored"]], bind: bind)
        let result = validated([.table(table), .text("keep")])
        XCTAssertEqual(result?.spec.blocks.first, .table(SpecTable(columns: table.columns, rows: nil, bind: bind)))
    }

    func testManifestFilteredToExistingReadAndLocal() {
        let result = validated([.text("x")], requests: ["review.flag", "library.words", "nope", "storage.get", "library.words"])
        XCTAssertEqual(result?.requests, ["library.words", "storage.get"])
    }

    func testRequestsAreUnionedWithBindsAndSorted() {
        let bind = SpecBind(capability: "stats.wordsPerDay", args: .object([:]))
        let table = SpecTable(columns: [SpecColumn(title: "D", field: "day")], rows: nil, bind: bind)
        let result = validated([.table(table)], requests: ["library.words"])
        XCTAssertEqual(result?.requests, ["library.words", "stats.wordsPerDay"])
    }

    func testDroppedBlockDoesNotContributeItsBind() {
        let bad = SpecTable(columns: [], rows: nil, bind: SpecBind(capability: "library.words"))
        let result = validated([.table(bad), .text("x")])
        XCTAssertEqual(result?.requests, [])
    }

    // MARK: validate: ids

    func testDuplicateIdsRenamedAcrossChecklistsAndRoadmaps() {
        let blocks: [SpecBlock] = [
            .checklist(id: "c1", items: ["a"]),
            .roadmap(id: "c1", steps: [SpecRoadmapStep(title: "s", detail: nil)]),
            .checklist(id: "c1", items: ["b"]),
        ]
        let ids = (validated(blocks)?.spec.blocks ?? []).compactMap { block -> String? in
            switch block {
            case .checklist(let id, _), .roadmap(let id, _): return id
            default: return nil
            }
        }
        XCTAssertEqual(ids, ["c1", "c1-2", "c1-3"])
    }

    func testEmptyIdsGetTypeDefaults() {
        let blocks: [SpecBlock] = [
            .checklist(id: " ", items: ["a"]),
            .checklist(id: "", items: ["b"]),
            .roadmap(id: "", steps: [SpecRoadmapStep(title: "s", detail: nil)]),
        ]
        let ids = (validated(blocks)?.spec.blocks ?? []).compactMap { block -> String? in
            switch block {
            case .checklist(let id, _), .roadmap(let id, _): return id
            default: return nil
            }
        }
        XCTAssertEqual(ids, ["checklist", "checklist-2", "roadmap"])
    }

    func testLongIdIsCappedSoStateKeyFits() {
        guard case .checklist(let id, _)? = validated([.checklist(id: chars(100), items: ["a"])])?.spec.blocks.first else { return XCTFail("expected a checklist") }
        XCTAssertEqual(id.count, 40)
        XCTAssertLessThanOrEqual("spec.\(id)".count, ArtifactLimits.maxStateKeyLength)
    }
}
