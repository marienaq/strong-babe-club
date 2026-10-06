import SwiftData
import SwiftUI
import WorkoutCore

@main
struct StrongBabeClubApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing") {
            // UI tests: in-memory data, fixed date (Mon Oct 19 2026), no disk writes.
            let clock = { Date(timeIntervalSince1970: 1_792_414_800) }
            _store = State(initialValue: AppStore(repository: InMemoryRepository(DebugRoute.empty ? StoredData() : UITestSeed.data()), clock: clock))
        } else {
            let repo: Repository
            do {
                repo = SwiftDataRepository(container: try SwiftDataRepository.makeContainer())
            } catch {
                Log.store.fault("store unavailable, using memory [\(Log.kind(error), privacy: .public)]")
                repo = InMemoryRepository()
            }
            _store = State(initialValue: AppStore(repository: repo))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .defaultAppStorage(AppDefaults.store)
                .overlay(alignment: .top) {
                    if DebugRoute.enabled {
                        Text("test mode · sample data · not saved")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.purple.opacity(0.85)))
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("testModeBadge")
                    }
                }
                .task {
                    store.load()
                    await store.prepare()
                    if let format = DebugRoute.metabolicFormat { await store.debugForceMetabolic(format) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.prepare() } }
                }
        }
    }
}
