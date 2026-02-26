import Foundation

public struct PQRNG {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public static func seed(from source: String) -> UInt64 {
        // 64-bit FNV-1a for stable string-to-seed mapping.
        var hash: UInt64 = 0xcbf29ce484222325
        for b in source.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public mutating func nextUInt64() -> UInt64 {
        // xorshift64*
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }

    public mutating func below(_ num: Int) -> Int {
        guard num > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(num))
    }

    public mutating func belowLow(_ num: Int) -> Int {
        min(below(num), below(num))
    }

    public mutating func odds(_ chance: Int, _ outOf: Int) -> Bool {
        below(outOf) < chance
    }

    public mutating func choice<T>(_ source: [T]) -> T {
        source[below(source.count)]
    }

    public mutating func choiceLow<T>(_ source: [T]) -> T {
        source[belowLow(source.count)]
    }
}
