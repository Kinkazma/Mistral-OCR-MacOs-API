import SwiftUI
import AppKit

@main
struct MistralOCRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appModel = MainWindowManager.shared.appModel
    
    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(appModel)
        }

        .commands {
            CommandMenu("Aide") {
                Button("Exporter les logs…") {
                    if let url = Logger.shared.exportToDownloads() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
    }
}
