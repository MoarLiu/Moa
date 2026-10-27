import Foundation

/// A snapshot of one explicitly selected thread, independent of billing aggregates.
struct CodexLiveSnapshot: Codable, Equatable {
    var threadID: String
    var turnID: String?
    var model: String?
    var tokensPerSecond: Double?
    var requestTokens: Int?
    var contextPercent: Double?
    var cachePercent: Double?
    var observedAt: Double?
    var state: String = "sampling"
}

struct CodexLiveMetrics {
    private struct Counts {
        var input: Int
        var cached: Int
        var output: Int
        var total: Int
        var signature: String

        init(_ values: [String: Any]) {
            func count(_ key: String) -> Int { max(0, (values[key] as? NSNumber)?.intValue ?? 0) }
            input = count("input_tokens")
            cached = min(input, count("cached_input_tokens"))
            output = count("output_tokens")
            total = count("total_tokens")
            signature = [input, cached, count("cache_write_input_tokens"), output].map(String.init).joined(separator: ":")
        }
    }

    private struct Sample {
        var date: Date
        var counts: Counts
        var cumulative: Counts?
        var responseID: String?
        var isRecord: Bool
    }

    let threadID: String
    private(set) var turnID: String?
    private(set) var model: String?
    private var contextWindow: Int?
    private var samples: [Sample] = []
    private var responseIDs: [String] = []
    private var latest: Counts?
    private var observedAt: Date?
    private var cacheInput = 0.0
    private var cacheRead = 0.0
    private var state = "sampling"

    init(threadID: String) { self.threadID = threadID }

    static func validThreadID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{7,127}$", options: .regularExpression) != nil
            && !["__proto__", "prototype", "constructor"].contains(value)
    }

    mutating func consume(_ data: Data) {
        guard data.count <= 512 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return }
        let event = payload["type"] as? String
        if kind == "turn_context" {
            selectTurn(payload["turn_id"] as? String)
            if let next = payload["model"] as? String, !next.isEmpty, next != model {
                if model != nil { clearSamples(); contextWindow = nil; latest = nil; observedAt = nil }
                model = next
            }
            return
        }
        if kind == "event_msg", event == "task_started" || event == "turn_started" {
            if let id = payload["turn_id"] as? String, id == turnID { return }
            reset(turn: payload["turn_id"] as? String)
            setWindow(payload["model_context_window"])
            return
        }
        if kind == "event_msg", ["task_complete", "turn_complete", "turn_completed"].contains(event ?? "") {
            if let id = payload["turn_id"] as? String, id != turnID { return }
            state = "completed"
            return
        }
        if kind == "event_msg", ["turn_aborted", "task_aborted", "task_failed"].contains(event ?? "") {
            if let id = payload["turn_id"] as? String, id != turnID { return }
            samples.removeAll(); state = "stopped"
            return
        }
        guard let timestamp = object["timestamp"] as? String,
              let date = CodexUsageDateParser.parse(timestamp) else { return }
        let isRecord = kind == "token_usage_record"
        let values: [String: Any]
        let cumulative: [String: Any]?
        if isRecord {
            if let id = payload["thread_id"] as? String, id != threadID { return }
            if let id = payload["session_id"] as? String, id != threadID { return }
            selectTurn(payload["turn_id"] as? String)
            if let next = payload["model"] as? String, !next.isEmpty, next != model {
                if model != nil { clearSamples(); contextWindow = nil }
                model = next
            }
            guard let usage = payload["usage"] as? [String: Any] else { return }
            values = usage
            cumulative = payload["thread_token_usage"] as? [String: Any]
        } else {
            guard kind == "event_msg", event == "token_count",
                  let info = payload["info"] as? [String: Any] else { return }
            setWindow(info["model_context_window"])
            guard let usage = info["last_token_usage"] as? [String: Any] else { return }
            values = usage
            cumulative = info["total_token_usage"] as? [String: Any]
        }
        // Parent history copied before a child receives its own context is not new output.
        guard model != nil else { return }
        let counts = Counts(values)
        guard counts.input > 0 || counts.output > 0 || counts.total > 0 else { return }
        let total = cumulative.map(Counts.init)
        let responseID = payload["response_id"] as? String
        if let responseID, !responseID.isEmpty {
            guard !responseIDs.contains(responseID) else { return }
            responseIDs.append(responseID)
            if responseIDs.count > 512 { responseIDs.removeFirst(responseIDs.count - 512) }
        }
        let sample = Sample(date: date, counts: counts, cumulative: total, responseID: responseID, isRecord: isRecord)
        var replacing: Counts?
        if let index = samples.lastIndex(where: { old in
            if let total, let previous = old.cumulative { return total.signature == previous.signature }
            return old.date == date && old.counts.signature == counts.signature
        }) {
            // A new-format record can replace its legacy mirror, never another response ID.
            if isRecord && !samples[index].isRecord { replacing = samples[index].counts; samples[index] = sample }
            else if !(isRecord && samples[index].isRecord && responseID != samples[index].responseID) { return }
            else { samples.append(sample) }
        } else {
            if let total, let previous = samples.last?.cumulative,
               total.output < previous.output || total.input < previous.input { clearSamples() }
            if let previous = samples.last {
                let seconds = date.timeIntervalSince(previous.date)
                if seconds < 0.5 || seconds > 120 { samples.removeAll() }
            }
            samples.append(sample)
        }
        cacheInput += Double(counts.input - (replacing?.input ?? 0))
        cacheRead += Double(counts.cached - (replacing?.cached ?? 0))
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
        latest = counts; observedAt = date; state = "active"
    }

    var snapshot: CodexLiveSnapshot {
        var intervals: [(Double, Double)] = []
        if turnID != nil {
            for (previous, current) in zip(samples, samples.dropFirst()) {
                let seconds = current.date.timeIntervalSince(previous.date)
                guard seconds >= 0.5, seconds <= 120 else { continue }
                let output: Int
                if let a = previous.cumulative, let b = current.cumulative {
                    guard b.output >= a.output, b.input >= a.input else { continue }
                    output = b.output - a.output
                } else { output = current.counts.output }
                if output > 0 { intervals.append((Double(output), seconds)) }
            }
        }
        let recent = intervals.suffix(3)
        let seconds = recent.reduce(0) { $0 + $1.1 }
        return CodexLiveSnapshot(
            threadID: threadID, turnID: turnID, model: model,
            tokensPerSecond: seconds > 0 ? recent.reduce(0) { $0 + $1.0 } / seconds : nil,
            requestTokens: latest?.total,
            contextPercent: contextWindow.flatMap { window in latest.map { Double($0.total) / Double(window) * 100 } },
            cachePercent: cacheInput > 0 ? cacheRead / cacheInput * 100 : nil,
            observedAt: observedAt?.timeIntervalSince1970, state: state)
    }

    private mutating func selectTurn(_ id: String?) {
        guard let id, !id.isEmpty, id != turnID else { return }
        reset(turn: id)
    }

    private mutating func reset(turn: String?) {
        turnID = turn; model = nil; contextWindow = nil
        clearSamples(); responseIDs.removeAll(); latest = nil; observedAt = nil; state = "sampling"
    }

    private mutating func clearSamples() {
        samples.removeAll(); cacheInput = 0; cacheRead = 0
    }

    private mutating func setWindow(_ value: Any?) {
        if let window = (value as? NSNumber)?.intValue, window > 0 { contextWindow = window }
    }
}
