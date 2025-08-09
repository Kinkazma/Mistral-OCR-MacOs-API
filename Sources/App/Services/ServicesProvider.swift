import AppKit
import UniformTypeIdentifiers

final class ServicesProvider: NSObject {
    /// Singleton instance used to register the services provider with NSApp.
    static let shared = ServicesProvider()
    // This selector name must match the NSMessage in Info.plist ("serviceCopy:").
    @objc func serviceCopy(_ pboard: NSPasteboard,
                           userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self],
                                            options: [.urlReadingFileURLsOnly: true]) as? [URL],
              let u = urls.first else { return }

        Task {
            do {
                let normalized = try FormatDetect.normalize(u)

                // Use the global setting for image inclusion.  The SettingsStore
                // property will handle persistence.
                let includeImgs = SettingsStore.shared.includeImages

                let result = try await OCRClient.shared.process(
                    normalized: normalized,
                    model: SettingsStore.shared.selectedModel,
                    includeImages: includeImgs,
                    outputKind: .markdown
                )

                await MainActor.run {
                    HistoryStore.shared.insert(from: u, normalized: normalized, result: result)
                }

                if let md = result.outputText as String? {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(md, forType: .string)
                }
            } catch {
                Logger.shared.error("ServicesProvider serviceCopy failed for \(u.path): \(error)")
            }
        }
    }
}
