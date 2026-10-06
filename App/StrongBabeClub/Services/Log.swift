import Foundation
import os

/// Privacy-safe logging. Only counts, durations and error *types* are logged
/// as public; anything that could be personal (notes, names, weights, dates)
/// is never logged, or is marked `.private` so it is redacted on device logs.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.marienaq.strongbabeclub"
    static let store = Logger(subsystem: subsystem, category: "store")
    static let planner = Logger(subsystem: subsystem, category: "planner")
    static let importer = Logger(subsystem: subsystem, category: "import")
    static let timer = Logger(subsystem: subsystem, category: "timer")

    /// A non-identifying description of an error (its type only).
    static func kind(_ error: Error) -> String { String(describing: type(of: error)) }
}
