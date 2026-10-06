import EnjinKit
import SwiftUI

@main
struct EnjinApp: App {
    private let store = NotebookStore(root: EnjinApp.storeRoot())
    @State private var settings = AppSettings()
    private let telemetry = Telemetry(url: EnjinApp.storeRoot().deletingLastPathComponent().appendingPathComponent("telemetry.jsonl"))

    private static func storeRoot() -> URL {
        // UI tests get a fresh, throwaway store on every launch.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingFreshStore") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString)")
        }
        return (try? NotebookStore.defaultRoot()) ?? FileManager.default.temporaryDirectory.appendingPathComponent("Notebooks")
    }

    var body: some Scene {
        WindowGroup {
            LibraryView(store: store, settings: settings, telemetry: telemetry)
                // Switches every screen's language live, without a restart.
                .environment(\.locale, settings.locale)
                .task { await telemetry.record("app_open") }
        }
    }
}
