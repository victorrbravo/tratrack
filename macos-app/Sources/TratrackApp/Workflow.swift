import Foundation

/// A workflow file. Two layouts are read:
/// - `examples/bogota.json`: `tasks` is an array, drawn in file order, and
///   each task carries its own `data` (summary, time, amount, ...).
/// - `examples/october.json`, `examples/pizza.json`: `tasks` is an object
///   keyed by task name, ordered by following the transitions from `initial`.
/// Only the fields the app shows are decoded; the rest are ignored.
struct Workflow: Decodable {
    var name: String?
    var data: Summary?
    var tasks: [WorkflowTask]

    struct Summary: Decodable {
        var amountField: String?
    }

    enum CodingKeys: String, CodingKey {
        case name, data, tasks, initial
    }

    /// Decodes the file's snake_case keys.
    static func decode(from data: Data) throws -> Workflow {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Workflow.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        data = try container.decodeIfPresent(Summary.self, forKey: .data)
        do {
            tasks = try container.decode([WorkflowTask].self, forKey: .tasks)
        } catch DecodingError.typeMismatch {
            let byName = try container.decode([String: WorkflowTask].self, forKey: .tasks)
            let initial = try container.decodeIfPresent(String.self, forKey: .initial)
            tasks = Self.route(byName, initial: initial)
        }
    }

    /// Orders keyed tasks by walking their first link from the initial task
    /// (e.g. `fk_status='Start'`). Tasks the walk never reaches come last, by name.
    private static func route(_ byName: [String: WorkflowTask], initial: String?) -> [WorkflowTask] {
        var start = initial?.firstMatch(of: #/'([^']+)'/#).map { String($0.1) }
        if start.map({ byName[$0] == nil }) ?? true {
            start = byName["Start"] != nil ? "Start" : byName.keys.sorted().first
        }

        var order: [String] = []
        var seen = Set<String>()
        var current = start
        while let name = current, byName[name] != nil, !seen.contains(name) {
            order.append(name)
            seen.insert(name)
            current = byName[name]?.transition?.links?.first?.task
        }
        order += byName.keys.filter { !seen.contains($0) }.sorted()

        return order.compactMap { name in
            guard var task = byName[name] else { return nil }
            task.name = name
            return task
        }
    }
}

struct WorkflowTask: Decodable {
    /// Keyed tasks have no `name` field; the key is filled in after decoding.
    var name: String
    var data: Details?
    var transition: Transition?

    enum CodingKeys: String, CodingKey {
        case name, data, transition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        data = try container.decodeIfPresent(Details.self, forKey: .data)
        transition = try container.decodeIfPresent(Transition.self, forKey: .transition)
    }

    struct Position: Decodable {
        var latitude: Double
        var longitude: Double
    }

    struct Details: Decodable {
        var timeField: String?
        var amountField: String?
        var summary: String?
        var tags: [String]?
        var id: Int?
        var tips: [String]?
        var tipsIdField: Int?
        var videos: [String]?
        var position: Position?
        var updateAtDiff: String?
        var distanceDiff: Double?

        // All fields use try? so a type mismatch on one field never kills the whole struct.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            timeField   = try? c.decodeIfPresent(String.self,   forKey: .timeField)
            amountField = try? c.decodeIfPresent(String.self,   forKey: .amountField)
            summary     = try? c.decodeIfPresent(String.self,   forKey: .summary)
            tags        = try? c.decodeIfPresent([String].self, forKey: .tags)
            tips        = try? c.decodeIfPresent([String].self, forKey: .tips)
            videos      = try? c.decodeIfPresent([String].self, forKey: .videos)
            position    = try? c.decodeIfPresent(Position.self, forKey: .position)

            // id can arrive as Int or Double
            if let i = try? c.decodeIfPresent(Int.self, forKey: .id) {
                id = i
            } else if let d = try? c.decodeIfPresent(Double.self, forKey: .id) {
                id = Int(d)
            }

            // tipsIdField can arrive as Int or Double
            if let i = try? c.decodeIfPresent(Int.self, forKey: .tipsIdField) {
                tipsIdField = i
            } else if let d = try? c.decodeIfPresent(Double.self, forKey: .tipsIdField) {
                tipsIdField = Int(d)
            }

            // updateAtDiff arrives as a duration string ("01:00:00" / "1h0m0s") or seconds as a number
            if let s = try? c.decodeIfPresent(String.self, forKey: .updateAtDiff) {
                updateAtDiff = s
            } else if let secs = try? c.decodeIfPresent(Double.self, forKey: .updateAtDiff), secs > 0 {
                let t = Int(secs)
                updateAtDiff = String(format: "%02d:%02d:00", t / 3600, (t % 3600) / 60)
            }

            // distanceDiff arrives as a number or a numeric string
            if let d = try? c.decodeIfPresent(Double.self, forKey: .distanceDiff) {
                distanceDiff = d
            } else if let s = try? c.decodeIfPresent(String.self, forKey: .distanceDiff) {
                distanceDiff = Double(s)
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, timeField, amountField, summary, tags, tips, tipsIdField, videos, position
            case updateAtDiff, distanceDiff
        }
    }

    struct Transition: Decodable {
        var links: [Link]?
        /// Set on the last task of a day, with that day's total.
        var wrapped: DayTotal?
    }

    struct Link: Decodable {
        var task: String
    }

    struct DayTotal: Decodable {
        var label: String?
        var amount: String?
    }
}

/// One task of the workflow, numbered in route order.
struct Step: Identifiable {
    let number: Int
    let task: WorkflowTask

    var id: Int { number }
    var name: String { task.name }
    var summary: String? { task.data?.summary }
    var amount: String? { task.data?.amountField }
    var videoCount: Int { task.data?.videos?.count ?? 0 }
    var tags: [String] { task.data?.tags ?? [] }
    var tips: [String] { task.data?.tips ?? [] }
    var tipsIdField: Int? { task.data?.tipsIdField }
    var taskDataId: Int? { task.data?.id }

    /// Geographic coordinate for this step, if available.
    /// The JSON stores the fields with lat/lon swapped, so we correct here.
    var coordinate: (lat: Double, lon: Double)? {
        guard let p = task.data?.position else { return nil }
        return (lat: p.longitude, lon: p.latitude)
    }
    var dayTotal: WorkflowTask.DayTotal? { task.transition?.wrapped }

    /// Humanised travel time from `update_at_diff`.
    /// Handles both "HH:MM:SS" (static files) and "1h30m0s" (server response).
    var travelTime: String? {
        guard let raw = task.data?.updateAtDiff, !raw.isEmpty else { return nil }
        let h: Int
        let m: Int
        if raw.contains(":") {
            // "HH:MM:SS"
            let parts = raw.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            h = parts[0]; m = parts[1]
        } else if raw.contains("h") || raw.contains("m") {
            // "1h30m0s" or "30m0s" — Go duration string
            let hMatch = raw.firstMatch(of: /(\d+)h/)
            let mMatch = raw.firstMatch(of: /(\d+)m/)
            h = hMatch.flatMap { Int($0.1) } ?? 0
            m = mMatch.flatMap { Int($0.1) } ?? 0
        } else {
            return nil
        }
        switch (h, m) {
        case (0, 0): return nil
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) hr"
        default:     return "\(h) hr \(m) min"
        }
    }

    /// Humanised travel distance from `distance_diff` (metres), e.g. "1.7 km" or "476 m".
    var travelDistance: String? {
        guard let metres = task.data?.distanceDiff, metres > 0 else { return nil }
        if metres >= 1000 {
            let km = metres / 1000
            return String(format: km < 10 ? "%.1f km" : "%.0f km", km)
        }
        return "\(Int(metres.rounded())) m"
    }

    /// Parses the first `videos` entry as `"<start> <end>"` seconds.
    var videoSegment: (start: Double, end: Double)? {
        guard let raw = task.data?.videos?.first else { return nil }
        let parts = raw.split(separator: " ")
        guard parts.count == 2,
              let s = Double(parts[0]), let e = Double(parts[1]) else { return nil }
        return (s, e)
    }

    /// Where the route goes next, e.g. "Then on to Venetto." Tasks without a
    /// summary (the keyed layout) show this instead.
    var nextDescription: String {
        let next = (task.transition?.links ?? []).map(\.task).filter { $0 != "END" }
        return next.isEmpty ? "End of the route." : "Then on to \(next.joined(separator: " or "))."
    }

    var time: Date? {
        guard let text = task.data?.timeField else { return nil }
        return (try? Date(text, strategy: .iso8601))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    /// Lowercased words from the name, summary and tags, for picking an icon.
    var keywords: Set<String> {
        let text = ([name, summary ?? ""] + (task.data?.tags ?? [])).joined(separator: " ")
        return Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }
}

extension Workflow {
    var steps: [Step] {
        tasks.enumerated().map { Step(number: $0.offset + 1, task: $0.element) }
    }
}
