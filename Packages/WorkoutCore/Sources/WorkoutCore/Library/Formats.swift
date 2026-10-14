import Foundation

/// Warm-up and cool-down constants. Metcon shapes live in `MetconCatalog`.
public enum FormatLibrary {
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
