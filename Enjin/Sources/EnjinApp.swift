import CoreText
import EnjinKit
import SwiftUI

@main
struct EnjinApp: App {
    private let store = NotebookStore(root: EnjinApp.storeRoot())
    @State private var settings = AppSettings()
    private let telemetry = Telemetry(url: EnjinApp.storeRoot().deletingLastPathComponent().appendingPathComponent("telemetry.jsonl"))

    init() {
        // Inter (OFL), bundled in Fonts/; registered here instead of UIAppFonts.
        let fonts = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }

    private static func storeRoot() -> URL {
        // UI tests get a fresh, throwaway store on every launch.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFreshStore") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString)")
        }
        return (try? NotebookStore.defaultRoot()) ?? FileManager.default.temporaryDirectory.appendingPathComponent("Notebooks")
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-designKit") {
            DesignKitView()
        } else {
            LibraryView(store: store, settings: settings, telemetry: telemetry)
        }
        #else
        LibraryView(store: store, settings: settings, telemetry: telemetry)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                // Switches every screen's language live, without a restart.
                .environment(\.locale, settings.locale)
                .font(Theme.body())
                .preferredColorScheme(.light)
                .tint(Theme.signal)
                .task { await telemetry.record("app_open") }
        }
    }
}
