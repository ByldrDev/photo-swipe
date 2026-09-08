import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Everything that differs between iOS (UIKit) and macOS (AppKit) lives here so
// the rest of the app can stay platform-neutral SwiftUI.

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

enum Platform {
    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif

    /// Window/system background behind the Home screen.
    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// Opens the place where the user can grant Photos access after denying it.
    static func openPhotoSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

extension View {
    /// iOS presents the deck as a full-screen cover; macOS swaps the window's
    /// root instead (see `RootView`), so this is a no-op there.
    @ViewBuilder
    func swipeCover(isPresented: Binding<Bool>, model: AppModel) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) { SwipeView().environment(model) }
        #else
        self
        #endif
    }

    @ViewBuilder
    func hidesStatusBar() -> some View {
        #if os(iOS)
        statusBarHidden()
        #else
        self
        #endif
    }

    /// `.navigationBarTitleDisplayMode(.inline)` where it exists.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Sheets on macOS size to their content, so give them a sensible frame.
    @ViewBuilder
    func sheetFrame() -> some View {
        #if os(macOS)
        frame(minWidth: 640, idealWidth: 760, minHeight: 480, idealHeight: 640)
        #else
        self
        #endif
    }
}
