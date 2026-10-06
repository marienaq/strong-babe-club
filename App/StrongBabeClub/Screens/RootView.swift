import SwiftUI
import WorkoutCore

/// Tab bar: Today / Journal / Progress / Settings.
@MainActor
struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = {
        switch DebugRoute.tab {
        case "journal": return .journal
        case "progress": return .progress
        case "settings": return .settings
        default: return .today
        }
    }()
    @State private var showBears = DebugRoute.open == "bears"
    @State private var showAnimals = DebugRoute.open == "animals"

    enum Tab: Hashable { case today, journal, progress, settings }

    var body: some View {
        if store.needsOnboarding {
            OnboardingView()
        } else {
            tabs
        }
    }

    var tabs: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed") }
                .tag(Tab.journal)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(Tab.progress)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(Palette.tangerineActive)
        .fullScreen(isPresented: $showBears) { BearGallery().onTapGesture { showBears = false } }
        .fullScreen(isPresented: $showAnimals) { AnimalGallery().onTapGesture { showAnimals = false } }
        .alert("Oops", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

/// Shared page chrome: dotted paper + margin, content inset past the margin,
/// with room at the bottom so everything scrolls clear of the tab bar.
struct JournalPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                    Color.clear.frame(height: 1).id("page-bottom")
                }
                .padding(.leading, 44)
                .padding(.trailing, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .background { PaperBackground() }
            .task {
                guard DebugRoute.scrollBottom || DebugRoute.scrollTarget != nil else { return }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if let target = DebugRoute.scrollTarget {
                    proxy.scrollTo(target, anchor: .center)
                } else {
                    proxy.scrollTo("page-bottom", anchor: .bottom)
                }
            }
        }
    }
}
