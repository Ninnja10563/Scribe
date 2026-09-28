import Foundation

/// Counters are independent at each nesting depth and reset when a list ends.
public struct ListNumbering {
    private var counters: [Int] = Array(repeating: 0, count: 9)
    private var kinds: [ListDescriptor.Kind?] = Array(repeating: nil, count: 9)
    public init() {}
    public mutating func marker(for descriptor: ListDescriptor?) -> String? {
        guard let descriptor else { counters = Array(repeating: 0, count: 9); kinds = Array(repeating: nil, count: 9); return nil }
        let level = max(0, min(8, descriptor.level))
        if kinds[level] != descriptor.kind { counters[level] = 0; kinds[level] = descriptor.kind }
        counters[level] = counters[level] == 0 ? descriptor.start : counters[level] + 1
        for i in (level + 1)..<9 { counters[i] = 0; kinds[i] = nil }
        let number = counters[level]
        switch descriptor.kind {
        case .bullet: return "•"
        case .decimal: return "\(number)."
        case .lowerAlpha:
            var n = number; var text = ""
            while n > 0 { n -= 1; text = String(UnicodeScalar(97 + n % 26)!) + text; n /= 26 }
            return text + "."
        case .lowerRoman:
            guard number < 4000 else { return "\(number)." }
            var n = number, result = ""
            for (value, symbol) in [(1000,"m"),(900,"cm"),(500,"d"),(400,"cd"),(100,"c"),(90,"xc"),(50,"l"),(40,"xl"),(10,"x"),(9,"ix"),(5,"v"),(4,"iv"),(1,"i")] {
                while n >= value { result += symbol; n -= value }
            }
            return result + "."
        }
    }
}
