import Foundation

/// Data protection for the on-device journal.
///
/// The store uses `FileProtectionType.complete`: files are encrypted with a key
/// that is discarded ~10 s after the device locks. The app does no background
/// work (no background modes; timer alerts are pre-scheduled local
/// notifications), and saves happen while the app is in the foreground, so
/// `.complete` is safe here. The target also sets the
/// `com.apple.developer.default-data-protection` entitlement to
/// `NSFileProtectionComplete` as a default for every file the app creates.
enum FileProtection {
    static func protectedStoreDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("StrongBabeClub", isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: attributes)
        return dir
    }

    /// Re-applies complete protection to the store files (SQLite + WAL/SHM).
    static func protectContents(of dir: URL) {
        #if os(iOS)
        let fm = FileManager.default
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dir.path)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files {
            do {
                try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: f.path)
            } catch {
                Log.store.error("file protection not applied [\(Log.kind(error), privacy: .public)]")
            }
        }
        #endif
    }

    /// Exports are written to a temporary, protected file and removed after sharing.
    static func temporaryExportURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
}
