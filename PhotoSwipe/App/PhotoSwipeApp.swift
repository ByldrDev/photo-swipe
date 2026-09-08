import SwiftUI

@main
struct PhotoSwipeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
                .onChange(of: model.library.libraryVersion) { _, _ in
                    model.rebaseSessionOnLibrary()
                }
        }
        .defaultSize(width: 960, height: 760)
    }
}

/// iOS: Home, with the deck presented as a full-screen cover from `HomeView`.
/// macOS: the window's root swaps between Home and the deck.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if os(macOS)
        ZStack {
            if model.isSwiping {
                SwipeView().transition(.opacity)
            } else {
                HomeView().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isSwiping)
        .frame(minWidth: 640, minHeight: 520)
        #else
        HomeView()
        #endif
    }
}
