import AgentBarCore
import Foundation

struct CodexTokenUsage: Codable, Equatable, Sendable {
    var input = 0
    var cached = 0
    var written = 0
    var output = 0

    static let zero = Self()

    init() {}

    init?(_ object: Any?) {
        guard let object = object as? [String: Any], object["input_tokens"] is NSNumber, object["output_tokens"] is NSNumber else { return nil }
        func count(_ key: String) -> Int { max(0, min((object[key] as? NSNumber)?.intValue ?? 0, Int.max / 16)) }
        input = count("input_tokens")
        cached = min(input, count("cached_input_tokens"))
        written = count("cache_write_input_tokens")
        output = count("output_tokens")
    }

    var tokens: TokenCount { TokenCount(input: max(0, input - cached), output: output, cacheRead: cached, cacheWrite: written) }
    var key: String { "\(input):\(cached):\(written):\(output)" }

    func delta(from previous: Self) -> Self? {
        guard input >= previous.input, cached >= previous.cached, written >= previous.written, output >= previous.output else { return nil }
        var delta = Self()
        delta.input = input - previous.input
        delta.cached = min(delta.input, cached - previous.cached)
        delta.written = written - previous.written
        delta.output = output - previous.output
        return delta
    }

    mutating func retainHighWater(_ value: Self) {
        input = max(input, value.input)
        cached = max(cached, value.cached)
        written = max(written, value.written)
        output = max(output, value.output)
    }
}
