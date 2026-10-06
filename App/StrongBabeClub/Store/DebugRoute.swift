import Foundation

/// Launch-argument hooks for UI tests and screenshots. Everything here is
/// ignored unless the app was launched with `-ui-testing` (which also swaps
/// in an in-memory store, so nothing touches real data).
///
///   -sbc-empty                 start with no data (fresh install)
///   -sbc-tab journal|progress|settings
///   -sbc-open session|why|finish|bears
///   -sbc-section warmup|strength|metabolic|cooldown
///   -sbc-metabolic tabata|interval|amrap_with_rest|for_time|emom|amrap
///   -sbc-scroll-bottom         scroll the page to the end
///   -sbc-expand                open "view history" panels
///
/// Test mode (`-ui-testing`) uses a FIXED date (Mon Oct 19 2026), sample data
/// in memory only, and its own preferences; a "test mode" badge is shown.
/// Never launch it on a simulator someone is using by hand: anything they do
/// in that process is thrown away. In Debug builds the navigation-only flags
/// (tab/open/section/scroll/expand) also work on real data without test mode.
enum DebugRoute {
    static let args = ProcessInfo.processInfo.arguments
    /// Test mode: fixed clock, in-memory sample data, separate preferences.
    static var enabled: Bool { args.contains("-ui-testing") }

    /// Navigation hooks: test mode, or any Debug build.
    static var navigationEnabled: Bool {
        #if DEBUG
        return true
        #else
        return enabled
        #endif
    }

    static func value(_ key: String, navigation: Bool = false) -> String? {
        guard navigation ? navigationEnabled : enabled, let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func flag(_ key: String, navigation: Bool = false) -> Bool { (navigation ? navigationEnabled : enabled) && args.contains(key) }

    static var tab: String? { value("-sbc-tab", navigation: true) }
    static var open: String? { value("-sbc-open", navigation: true) }
    static var section: String? { value("-sbc-section", navigation: true) }
    static var scrollBottom: Bool { flag("-sbc-scroll-bottom", navigation: true) }
    static var expandHistory: Bool { flag("-sbc-expand", navigation: true) }
    // State-changing hooks: test mode only.
    static var metabolicFormat: String? { value("-sbc-metabolic") }
    static var empty: Bool { flag("-sbc-empty") }
}

/// Preferences store: the real one normally, a throwaway suite in test mode.
enum AppDefaults {
    static let store: UserDefaults = {
        guard DebugRoute.enabled, let suite = UserDefaults(suiteName: "com.marienaq.strongbabeclub.ui-testing") else { return .standard }
        suite.removePersistentDomain(forName: "com.marienaq.strongbabeclub.ui-testing")
        return suite
    }()
}
