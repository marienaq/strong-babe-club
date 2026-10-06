import SwiftUI

// Small shims so the views compile for iOS (the product) and can also be
// type-checked on macOS during development without full Xcode.

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension View {
    /// Number pad on iPhone.
    @ViewBuilder func numberKeyboard(decimal: Bool = true) -> some View {
        #if os(iOS)
        self.keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }

    /// Lists show reorder handles (iOS edit mode).
    @ViewBuilder func alwaysEditing() -> some View {
        #if os(iOS)
        self.environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }

    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Full-screen on iPhone, a sheet elsewhere.
    @ViewBuilder func fullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

enum Haptics {
    enum Kind { case tap, success, warning, phaseChange, rest }

    @MainActor static func play(_ kind: Kind) {
        #if os(iOS)
        switch kind {
        case .tap: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .phaseChange: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .rest: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 1)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}

@MainActor
func hideKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}
