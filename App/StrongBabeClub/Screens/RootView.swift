import SwiftUI
import WorkoutCore

/// Tab bar: Today / Journal / Progress / Settings.
@MainActor
struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .today

    enum Tab: Hashable { case today, journal, progress, settings }

    var body: some View {
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
        .alert("Oops", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

/// Shared page chrome: dotted paper + margin, content inset past the margin.
struct JournalPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.leading, 44)
                    .padding(.trailing, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
        }
    }
}
