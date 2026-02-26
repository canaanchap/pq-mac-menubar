import Foundation

public enum PQLingo {
    public static func formatFloat(_ num: Double) -> String {
        var ret = String(format: "%.01f", num)
        if ret.hasSuffix("0") {
            ret = String(ret.dropLast(2))
        }
        return ret
    }

    public static func formatTimespan(_ timespan: TimeInterval) -> String {
        var num = timespan
        if num < 60.0 { return "~\(Int(num))s" }
        num /= 60
        if num < 60.0 { return "~\(Int(num))m" }
        num /= 60
        if num < 24.0 { return "~\(formatFloat(num))h" }
        num /= 24
        return "~\(formatFloat(num))d"
    }

    public static func toRoman(_ value: Int) -> String {
        if value == 0 { return "N" }
        var num = value
        var ret = ""
        if num < 0 {
            ret = "-"
            num = -num
        }

        let mapping: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]

        for (n, s) in mapping {
            while num >= n {
                num -= n
                ret += s
            }
        }
        return ret
    }

    public static func actName(_ act: Int) -> String {
        act == 0 ? "Prologue" : "Act \(toRoman(act))"
    }

    public static func plural(_ subject: String) -> String {
        if subject.hasSuffix("y") { return String(subject.dropLast()) + "ies" }
        if subject.hasSuffix("us") { return String(subject.dropLast(2)) + "i" }
        if subject.hasSuffix("ch") || subject.hasSuffix("x") || subject.hasSuffix("s") || subject.hasSuffix("sh") { return subject + "es" }
        if subject.hasSuffix("f") { return String(subject.dropLast()) + "ves" }
        if subject.hasSuffix("man") || subject.hasSuffix("Man") { return String(subject.dropLast(2)) + "en" }
        return subject + "s"
    }

    public static func indefinite(_ subject: String, qty: Int) -> String {
        if qty == 1 {
            let vowels = "AEIOU?aeiou?"
            if let first = subject.first, vowels.contains(first) {
                return "an \(subject)"
            }
            return "a \(subject)"
        }
        return "\(qty) \(plural(subject))"
    }

    public static func definite(_ subject: String, qty: Int) -> String {
        let s = qty > 1 ? plural(subject) : subject
        return "the \(s)"
    }

    static func prefix(_ values: [String], _ m: Int, _ subject: String, _ sep: String = " ") -> String {
        let t = abs(m)
        if t < 1 || t > values.count { return subject }
        return values[t - 1] + sep + subject
    }

    public static func sick(_ m: Int, _ subject: String) -> String {
        prefix(["dead", "comatose", "crippled", "sick", "undernourished"], 6 - abs(m), subject)
    }

    public static func young(_ m: Int, _ subject: String) -> String {
        prefix(["foetal", "baby", "preadolescent", "teenage", "underage"], 6 - abs(m), subject)
    }

    public static func big(_ m: Int, _ subject: String) -> String {
        prefix(["greater", "massive", "enormous", "giant", "titanic"], m, subject)
    }

    public static func special(_ m: Int, _ subject: String) -> String {
        if subject.contains(" ") {
            return prefix(["veteran", "cursed", "warrior", "undead", "demon"], m, subject)
        }
        return prefix(["Battle-", "cursed ", "Were-", "undead ", "demon "], m, subject, "")
    }

    public static func generateName(rng: inout PQRNG) -> String {
        let parts = [
            ["br", "cr", "dr", "fr", "gr", "j", "kr", "l", "m", "n", "pr", "", "", "", "r", "sh", "tr", "v", "wh", "x", "y", "z"],
            ["a", "a", "e", "e", "i", "i", "o", "o", "u", "u", "ae", "ie", "oo", "ou"],
            ["b", "ck", "d", "g", "k", "m", "n", "p", "t", "v", "x", "z"],
        ]

        var out = ""
        for i in 0..<6 {
            out += rng.choice(parts[i % 3])
        }
        if out.isEmpty { return "Nameless" }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}
