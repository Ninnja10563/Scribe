import Foundation

/// Numbering state is shared by series, with a separate contiguous-list mode for older files.
public struct ListNumbering {
    private struct State {
        var counters = Array(repeating: 0, count: 9)
        var kinds: [ListDescriptor.Kind?] = Array(repeating: nil, count: 9)
    }
    private var anonymous = State()
    private var series: [UUID: State] = [:]
    public init() {}
    public mutating func number(for descriptor: ListDescriptor?) -> Int? {
        guard let descriptor else { anonymous = State(); return nil }
        let level = max(0, min(8, descriptor.level))
        var state = descriptor.seriesID.flatMap { series[$0] } ?? (descriptor.seriesID == nil ? anonymous : State())
        if state.kinds[level] != descriptor.kind || descriptor.restart == true {
            state.counters[level] = 0; state.kinds[level] = descriptor.kind
        }
        state.counters[level] = state.counters[level] == 0 ? max(1, descriptor.start) : state.counters[level] + 1
        for i in (level + 1)..<9 { state.counters[i] = 0; state.kinds[i] = nil }
        if let id = descriptor.seriesID { series[id] = state } else { anonymous = state }
        return state.counters[level]
    }
    public mutating func marker(for descriptor: ListDescriptor?) -> String? {
        guard let number = number(for: descriptor), let descriptor else { return nil }
        return Self.marker(number: number, kind: descriptor.kind)
    }
    public static func marker(number: Int, kind: ListDescriptor.Kind) -> String {
        switch kind {
        case .bullet: return "•"
        case .decimal: return "\(number)."
        case .lowerAlpha, .upperAlpha:
            var n = number; var text = ""
            while n > 0 { n -= 1; text = String(UnicodeScalar(97 + n % 26)!) + text; n /= 26 }
            return (kind == .upperAlpha ? text.uppercased() : text) + "."
        case .lowerRoman, .upperRoman:
            guard number < 4000 else { return "\(number)." }
            var n = number, result = ""
            for (value, symbol) in [(1000,"m"),(900,"cm"),(500,"d"),(400,"cd"),(100,"c"),(90,"xc"),(50,"l"),(40,"xl"),(10,"x"),(9,"ix"),(5,"v"),(4,"iv"),(1,"i")] {
                while n >= value { result += symbol; n -= value }
            }
            return (kind == .upperRoman ? result.uppercased() : result) + "."
        }
    }
}
