import Foundation

/// A metabolic format with its typical rounds / times.
public struct MetabolicTemplate: Hashable, Sendable {
    public enum Intensity: Sendable { case low, mid, high }

    public var format: SectionFormat
    public var rounds: Int
    public var workSec: Int?
    public var restSec: Int?
    public var durationMin: Int?
    public var repsScheme: String?
    public var moveCount: Int
    public var intensity: Intensity

    /// Estimated minutes (used to fit the target length).
    public var minutes: Int {
        if let d = durationMin { return d }
        if let w = workSec { return max(1, Int((Double(rounds * (w + (restSec ?? 0))) / 60).rounded())) }
        return 12
    }

    /// Time component of the name (`amrap-5-4-...` uses the 4 min AMRAP).
    public var nameMinutes: Int {
        if format == .amrapWithRest { return max(1, (workSec ?? 60) / 60) }
        return minutes
    }

    public var instructions: String {
        switch format {
        case .amrapWithRest:
            let w = (workSec ?? 240) / 60
            let r = restSec ?? 60
            let rest = r % 60 == 0 ? "\(r / 60) min" : "\(r) s"
            return "\(rounds) rounds · as many as you can in \(w) min · rest \(rest)"
        case .amrap:
            return "As many rounds as you can in \(durationMin ?? 12) min"
        case .interval:
            return "\(rounds) rounds · \(workSec ?? 40) s work / \(restSec ?? 20) s rest"
        case .forTime:
            return "\(repsScheme ?? "21-15-9") for time · cap \(durationMin ?? 15) min"
        case .tabata:
            return "Tabata: \(rounds) × 20 s work / 10 s rest per move"
        case .emom:
            return "Every minute for \(durationMin ?? 12) min · alternate the moves"
        default:
            return "\(rounds) rounds"
        }
    }
}

public enum FormatLibrary {
    /// Metabolic formats seen in the coach's sheet: interval, AMRAP with rest,
    /// descending ladder for time, Tabata and EMOM.
    public static let metabolic: [MetabolicTemplate] = [
        MetabolicTemplate(format: .amrapWithRest, rounds: 5, workSec: 240, restSec: 60, moveCount: 3, intensity: .low),
        MetabolicTemplate(format: .amrapWithRest, rounds: 4, workSec: 180, restSec: 60, moveCount: 3, intensity: .low),
        MetabolicTemplate(format: .amrapWithRest, rounds: 3, workSec: 300, restSec: 60, moveCount: 3, intensity: .low),
        MetabolicTemplate(format: .amrap, rounds: 1, durationMin: 12, moveCount: 3, intensity: .mid),
        MetabolicTemplate(format: .amrap, rounds: 1, durationMin: 15, moveCount: 4, intensity: .mid),
        MetabolicTemplate(format: .interval, rounds: 6, workSec: 40, restSec: 20, moveCount: 3, intensity: .mid),
        MetabolicTemplate(format: .interval, rounds: 8, workSec: 45, restSec: 15, moveCount: 4, intensity: .mid),
        MetabolicTemplate(format: .forTime, rounds: 1, durationMin: 15, repsScheme: "21-15-9", moveCount: 2, intensity: .high),
        MetabolicTemplate(format: .forTime, rounds: 1, durationMin: 15, repsScheme: "10-8-6-4-2", moveCount: 3, intensity: .mid),
        MetabolicTemplate(format: .tabata, rounds: 8, workSec: 20, restSec: 10, durationMin: 8, moveCount: 2, intensity: .mid),
        MetabolicTemplate(format: .emom, rounds: 12, workSec: 60, durationMin: 12, moveCount: 3, intensity: .low),
    ]

    /// Short pieces for the test week ("short metabolic pieces still run").
    public static let short: [MetabolicTemplate] = [
        MetabolicTemplate(format: .amrap, rounds: 1, durationMin: 8, moveCount: 3, intensity: .mid),
        MetabolicTemplate(format: .tabata, rounds: 8, workSec: 20, restSec: 10, durationMin: 8, moveCount: 2, intensity: .mid),
        MetabolicTemplate(format: .emom, rounds: 8, workSec: 60, durationMin: 8, moveCount: 2, intensity: .low),
    ]

    public static let warmupRounds = 3
    /// "15-15-15-15-15" core work.
    public static let coreScheme = "15-15-15-15-15"
    public static let coreTimedSets = 5
}

/// `structure-rounds-time-word` names, e.g. `amrap-5-4-fungi`.
public enum WorkoutNamer {
    /// Curated, friendly, one-word nouns.
    public static let words: [String] = [
        "acorn", "alpaca", "anchor", "apricot", "aurora", "avocado", "badger", "bagel", "bamboo", "banjo",
        "basil", "beacon", "biscuit", "blossom", "bonsai", "breeze", "brownie", "bubble", "buttercup", "cactus",
        "canyon", "caramel", "cashew", "cedar", "cherry", "chipmunk", "cinnamon", "clover", "cobalt", "coconut",
        "comet", "cookie", "coral", "cosmos", "cricket", "crumpet", "cupcake", "daisy", "dandelion", "doodle",
        "dumpling", "ember", "falcon", "fern", "fig", "firefly", "flamingo", "fungi", "gecko", "ginger",
        "glacier", "gnocchi", "grape", "hazel", "hedgehog", "honey", "iris", "jasmine", "jellybean", "juniper",
        "kiwi", "koala", "lagoon", "lantern", "lemon", "lilac", "lotus", "mango", "maple", "marble",
        "meadow", "meteor", "mochi", "moss", "muffin", "nebula", "noodle", "nutmeg", "oasis", "otter",
        "papaya", "peach", "pebble", "pepper", "pickle", "pinecone", "pistachio", "pixel", "plum", "pretzel",
        "puffin", "pumpkin", "quokka", "radish", "raven", "ripple", "rocket", "saffron", "sequoia", "sesame",
        "sparrow", "sprout", "sundae", "sushi", "taco", "thistle", "tofu", "toucan", "truffle", "tulip",
        "turnip", "velvet", "violet", "waffle", "walrus", "willow", "yeti", "zephyr", "zinnia", "zucchini",
    ]

    public static func name<G: RandomNumberGenerator>(format: SectionFormat, rounds: Int, minutes: Int,
                                                     using rng: inout G, avoiding used: Set<String> = []) -> String {
        let prefix = "\(format.nameStructure)-\(max(1, rounds))-\(max(1, minutes))"
        let shuffled = words.seededShuffled(using: &rng)
        for w in shuffled where !used.contains("\(prefix)-\(w)") { return "\(prefix)-\(w)" }
        // Every word taken for this prefix: add a counter.
        var n = 2
        while used.contains("\(prefix)-\(shuffled[0])-\(n)") { n += 1 }
        return "\(prefix)-\(shuffled[0])-\(n)"
    }

    /// Validates a name: lowercase letters, digits and dashes, 3...60 chars.
    public static func isValid(_ name: String) -> Bool {
        guard (3...60).contains(name.count) else { return false }
        return name.allSatisfy { ($0.isLetter && $0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "-" }
    }
}
