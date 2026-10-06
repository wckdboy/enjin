import SwiftUI

@main
struct EnjinApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        CanvasScreen()
    }
}
