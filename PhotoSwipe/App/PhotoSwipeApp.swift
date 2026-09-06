import SwiftUI

@main
struct PhotoSwipeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
                .onChange(of: model.library.libraryVersion) { _, _ in
                    model.rebaseSessionOnLibrary()
                }
        }
    }
}
