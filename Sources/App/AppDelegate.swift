import AppKit

// Register global hotkeys and handle URL scheme callbacks for the application.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider.shared
        status = StatusController()
        status?.install()
        // Register the initial global hotkey according to stored settings.  This will log an
        // error if the key combination is already taken by another application.
        GlobalHotkeyManager.shared.register(defaultKey: SettingsStore.shared.hotkeyKeyCode,
                                            modifiers: SettingsStore.shared.hotkeyModifiers)

        // Start deposit folder watching after SettingsStore is fully initialized.  This
        // ensures that the singleton initialization does not recursively invoke
        // itself (which would cause a crash) and that any persisted deposit
        // settings are applied on launch.
        DepositWatcher.shared.updatePaths()
        MainWindowManager.shared.show()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
            if !flag {
                MainWindowManager.shared.show()
            }
            return true
        }

    /// Handle custom URL scheme (mistralocr://process?bookmark=…) passed to the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "mistralocr" {
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let b64 = comps.queryItems?.first(where: { $0.name == "bookmark" })?.value,
                  let data = Data(base64Encoded: b64) else { continue }
            var isStale = false
            if let fileURL = try? URL(resolvingBookmarkData: data,
                                      options: .withSecurityScope,
                                      relativeTo: nil,
                                      bookmarkDataIsStale: &isStale) {
                Task {
                    do {
                        let normalized = try FormatDetect.normalize(fileURL)
                        let result = try await OCRClient.shared.process(normalized: normalized,
                                                                        model: SettingsStore.shared.selectedModel,
                                                                        includeImages: SettingsStore.shared.includeImages,
                                                                        outputKind: .markdown)
                        await MainActor.run {
                            HistoryStore.shared.insert(from: fileURL, normalized: normalized, result: result)
                        }
                    } catch {
                        Logger.shared.error("URL scheme OCR failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

