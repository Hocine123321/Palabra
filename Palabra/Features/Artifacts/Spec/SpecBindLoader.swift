import Foundation

enum SpecBindResult<T: Equatable>: Equatable {
    case loaded(T)
    case failed(String)
}

struct ResolvedTable: Equatable {
    var columns: [String]
    var rows: [[String]]
}

struct ResolvedChartSeries: Equatable {
    var name: String?
    var values: [Double]
}

struct ResolvedChart: Equatable {
    var labels: [String]
    var series: [ResolvedChartSeries]
    /// The first series — what a bound chart plots.
    var values: [Double] { series.first?.values ?? [] }
}

/// Turns a table/chart block into display-ready data: inline data passes through,
/// a bind calls the registry. Never throws; a failure is a message the view shows inline.
enum SpecBindLoader {
    static let loadFailedMessage = "Couldn't load data"

    static func table(_ table: SpecTable, registry: CapabilityRegistry, session: ArtifactSession, granted: Set<String>) async -> SpecBindResult<ResolvedTable> {
        let titles = table.columns.map(\.title)
        guard let bind = table.bind else {
            return .loaded(ResolvedTable(columns: titles, rows: Array((table.rows ?? []).prefix(SpecLimits.maxTableRows))))
        }
        guard let items = await load(bind, registry: registry, session: session, granted: granted) else {
            return .failed(loadFailedMessage)
        }
        let keys = table.columns.map { $0.field ?? $0.title }
        let rows: [[String]] = items.compactMap { item in
            guard case .object(let object) = item else { return nil }
            return keys.map { stringify(object[$0]) }
        }
        return .loaded(ResolvedTable(columns: titles, rows: Array(rows.prefix(SpecLimits.maxTableRows))))
    }

    static func chart(_ chart: SpecChart, registry: CapabilityRegistry, session: ArtifactSession, granted: Set<String>) async -> SpecBindResult<ResolvedChart> {
        guard let bind = chart.bind else {
            let series = (chart.series ?? []).map { ResolvedChartSeries(name: $0.name, values: Array($0.values.prefix(SpecLimits.maxChartPoints))) }
            return .loaded(ResolvedChart(labels: Array((chart.labels ?? []).prefix(SpecLimits.maxChartPoints)), series: series))
        }
        guard let items = await load(bind, registry: registry, session: session, granted: granted),
              let labelField = chart.labelField, let valueField = chart.valueField else {
            return .failed(loadFailedMessage)
        }
        var labels: [String] = []
        var values: [Double] = []
        for item in items {
            guard case .object(let object) = item, let value = number(object[valueField]) else { continue }
            labels.append(stringify(object[labelField]))
            values.append(value)
            if values.count == SpecLimits.maxChartPoints { break }
        }
        return .loaded(ResolvedChart(labels: labels, series: [ResolvedChartSeries(name: nil, values: values)]))
    }

    /// The bound capability's result as an array, or nil on any failure.
    private static func load(_ bind: SpecBind, registry: CapabilityRegistry, session: ArtifactSession, granted: Set<String>) async -> [JSONValue]? {
        switch await registry.call(name: bind.capability, args: bind.args, session: session, granted: granted) {
        case .success(.array(let items)): return items
        case .success, .failure: return nil
        }
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case .number(let number)?: return number.isFinite ? number : nil
        case .string(let text)?: return Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    /// Integral numbers without `.0`; arrays joined with ", "; null -> "".
    static func stringify(_ value: JSONValue?) -> String {
        switch value {
        case nil, .null?: return ""
        case .string(let text)?: return text
        case .bool(let flag)?: return flag ? "true" : "false"
        case .number(let number)?:
            return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .array(let items)?: return items.map { stringify($0) }.joined(separator: ", ")
        case .object?: return value?.jsonString ?? ""
        }
    }
}
