import Foundation

/// Decodes one element but turns any failure into `nil`, so one bad block never loses the rest.
struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

/// Accepts a string, number or bool where the AI should have sent a string.
private struct FlexibleString: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Double.self) {
            value = number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        } else if let flag = try? container.decode(Bool.self) {
            value = flag ? "true" : "false"
        } else if container.decodeNil() {
            value = ""
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a string")
        }
    }
}

struct SpecColumn: Codable, Equatable, Sendable {
    var title: String
    var field: String?
}

/// A live data source for a table or chart: a `.read` capability plus its arguments.
struct SpecBind: Codable, Equatable, Sendable {
    var capability: String
    var args: JSONValue

    init(capability: String, args: JSONValue = .object([:])) {
        self.capability = capability
        self.args = args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capability = try container.decode(String.self, forKey: .capability)
        args = try container.decodeIfPresent(JSONValue.self, forKey: .args) ?? .object([:])
    }

    private enum CodingKeys: String, CodingKey { case capability, args }
}

struct SpecTable: Equatable, Sendable {
    var columns: [SpecColumn]
    var rows: [[String]]?
    var bind: SpecBind?
}

enum SpecChartStyle: String, Codable, Sendable {
    case bar
    case line
}

struct SpecChartSeries: Codable, Equatable, Sendable {
    var name: String?
    var values: [Double]
}

struct SpecChart: Equatable, Sendable {
    var style: SpecChartStyle
    var title: String?
    var labels: [String]?
    var series: [SpecChartSeries]?
    var bind: SpecBind?
    var labelField: String?
    var valueField: String?
}

struct SpecStatTile: Codable, Equatable, Sendable {
    var label: String
    var value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(FlexibleString.self, forKey: .label)?.value ?? ""
        value = try container.decodeIfPresent(FlexibleString.self, forKey: .value)?.value ?? ""
    }

    private enum CodingKeys: String, CodingKey { case label, value }
}

struct SpecRoadmapStep: Codable, Equatable, Sendable {
    var title: String
    var detail: String?
}

/// One renderable block. Decoded by the `type` key; the wire shapes are in `catalog`.
indirect enum SpecBlock: Codable, Equatable, Sendable {
    case heading(level: Int, text: String)
    case text(String)
    case list(ordered: Bool, items: [String])
    case table(SpecTable)
    case chart(SpecChart)
    case stats([SpecStatTile])
    case checklist(id: String, items: [String])
    case roadmap(id: String, steps: [SpecRoadmapStep])
    case columns([SpecBlock])
    case section(title: String, children: [SpecBlock])

    private enum CodingKeys: String, CodingKey {
        case type, level, text, ordered, items, columns, rows, bind, style, title
        case labels, series, labelField, valueField, tiles, id, steps, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        func strings(_ key: CodingKeys) throws -> [String] {
            try c.decode([FlexibleString].self, forKey: key).map(\.value)
        }
        switch type {
        case "heading":
            self = .heading(level: try c.decodeIfPresent(Int.self, forKey: .level) ?? 1, text: try c.decode(FlexibleString.self, forKey: .text).value)
        case "text":
            self = .text(try c.decode(FlexibleString.self, forKey: .text).value)
        case "list":
            self = .list(ordered: try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false, items: try strings(.items))
        case "table":
            let rows = try c.decodeIfPresent([[FlexibleString]].self, forKey: .rows)?.map { $0.map(\.value) }
            self = .table(SpecTable(
                columns: try c.decode([SpecColumn].self, forKey: .columns),
                rows: rows,
                bind: try c.decodeIfPresent(SpecBind.self, forKey: .bind)
            ))
        case "chart":
            self = .chart(SpecChart(
                style: try c.decodeIfPresent(SpecChartStyle.self, forKey: .style) ?? .bar,
                title: try c.decodeIfPresent(FlexibleString.self, forKey: .title)?.value,
                labels: try c.decodeIfPresent([FlexibleString].self, forKey: .labels)?.map(\.value),
                series: try c.decodeIfPresent([SpecChartSeries].self, forKey: .series),
                bind: try c.decodeIfPresent(SpecBind.self, forKey: .bind),
                labelField: try c.decodeIfPresent(String.self, forKey: .labelField),
                valueField: try c.decodeIfPresent(String.self, forKey: .valueField)
            ))
        case "stats":
            self = .stats(try c.decode([SpecStatTile].self, forKey: .tiles))
        case "checklist":
            self = .checklist(id: try c.decodeIfPresent(FlexibleString.self, forKey: .id)?.value ?? "", items: try strings(.items))
        case "roadmap":
            self = .roadmap(id: try c.decodeIfPresent(FlexibleString.self, forKey: .id)?.value ?? "", steps: try c.decode([SpecRoadmapStep].self, forKey: .steps))
        case "columns":
            self = .columns(try c.decode([LossyDecodable<SpecBlock>].self, forKey: .children).compactMap(\.value))
        case "section":
            self = .section(
                title: try c.decodeIfPresent(FlexibleString.self, forKey: .title)?.value ?? "",
                children: try c.decode([LossyDecodable<SpecBlock>].self, forKey: .children).compactMap(\.value)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown block type \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let text):
            try c.encode("heading", forKey: .type)
            try c.encode(level, forKey: .level)
            try c.encode(text, forKey: .text)
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .list(let ordered, let items):
            try c.encode("list", forKey: .type)
            try c.encode(ordered, forKey: .ordered)
            try c.encode(items, forKey: .items)
        case .table(let table):
            try c.encode("table", forKey: .type)
            try c.encode(table.columns, forKey: .columns)
            try c.encodeIfPresent(table.rows, forKey: .rows)
            try c.encodeIfPresent(table.bind, forKey: .bind)
        case .chart(let chart):
            try c.encode("chart", forKey: .type)
            try c.encode(chart.style, forKey: .style)
            try c.encodeIfPresent(chart.title, forKey: .title)
            try c.encodeIfPresent(chart.labels, forKey: .labels)
            try c.encodeIfPresent(chart.series, forKey: .series)
            try c.encodeIfPresent(chart.bind, forKey: .bind)
            try c.encodeIfPresent(chart.labelField, forKey: .labelField)
            try c.encodeIfPresent(chart.valueField, forKey: .valueField)
        case .stats(let tiles):
            try c.encode("stats", forKey: .type)
            try c.encode(tiles, forKey: .tiles)
        case .checklist(let id, let items):
            try c.encode("checklist", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(items, forKey: .items)
        case .roadmap(let id, let steps):
            try c.encode("roadmap", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(steps, forKey: .steps)
        case .columns(let children):
            try c.encode("columns", forKey: .type)
            try c.encode(children, forKey: .children)
        case .section(let title, let children):
            try c.encode("section", forKey: .type)
            try c.encode(title, forKey: .title)
            try c.encode(children, forKey: .children)
        }
    }

    /// The block catalog as shown to the AI. Keep in sync with the cases above.
    static let catalog: String = """
    {"type":"heading","level":1,"text":"…"}  level 1-3
    {"type":"text","text":"…"}
    {"type":"list","ordered":false,"items":["…"]}
    {"type":"table","columns":[{"title":"Day"}],"rows":[["Lunes"]]}
    {"type":"table","columns":[{"title":"Word","field":"spanish"}],"bind":{"capability":"library.words","args":{"limit":10}}}
    {"type":"chart","style":"bar"|"line","title":"…","labels":["Mon","Tue"],"series":[{"name":"Words","values":[3,5]}]}
    {"type":"chart","style":"line","bind":{"capability":"stats.wordsPerDay","args":{"days":14}},"labelField":"day","valueField":"count"}
    {"type":"stats","tiles":[{"label":"Words","value":"42"}]}
    {"type":"checklist","id":"c1","items":["…"]}  ticks are remembered by the app
    {"type":"roadmap","id":"r1","steps":[{"title":"…","detail":"…"}]}  step completion is remembered by the app
    {"type":"columns","children":[ …blocks… ]}
    {"type":"section","title":"…","children":[ …blocks… ]}
    "bind" is allowed only on table and chart, only to a read capability. A bound table maps each column's "field" onto the returned objects; a bound chart plots "valueField" against "labelField".
    """
}

struct ArtifactSpec: Codable, Equatable, Sendable {
    var blocks: [SpecBlock]

    init(blocks: [SpecBlock]) { self.blocks = blocks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decode([LossyDecodable<SpecBlock>].self, forKey: .blocks).compactMap(\.value)
    }

    private enum CodingKeys: String, CodingKey { case blocks }
}
