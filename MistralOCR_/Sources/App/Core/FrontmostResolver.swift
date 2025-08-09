import AppKit

enum FrontmostResolver {
    static func processFrontmost() {
        let urls = resolveSelectedFileURLs()
        if urls.isEmpty == false {
            Task {
                for u in urls {
                    do {
                        let normalized = try FormatDetect.normalize(u)
                        let result = try await OCRClient.shared.process(normalized: normalized,
                                                                        model: SettingsStore.shared.selectedModel,
                                                                        includeImages: SettingsStore.shared.includeImages,
                                                                        outputKind: .markdown)
                        await MainActor.run {
                            HistoryStore.shared.insert(from: u, normalized: normalized, result: result)
                        }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.outputText, forType: .string)
                    } catch {
                        Logger.shared.error("Hotkey OCR failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            if let w = NSApp.windows.first { w.makeKeyAndOrderFront(nil) }
        }
    }
    
    static func resolveSelectedFileURLs() -> [URL] {
        // 1) Finder selection
        if let finderURLs = executeAppleScript(source: """
            tell application "Finder"
                set theSelection to selection as alias list
                set out to {}
                repeat with a in theSelection
                    set end of out to POSIX path of (a as text)
                end repeat
                return out
            end tell
        """) {
            let urls = finderURLs.compactMap { URL(fileURLWithPath: $0) }
            if urls.isEmpty == false { return urls }
        }
        // 2) Preview front document
        if let previewPath = executeAppleScript(source: """
            tell application "Preview"
                if (count of documents) > 0 then
                    return POSIX path of (path of front document as text)
                else
                    return ""
                end if
            end tell
        """)?.first, previewPath.isEmpty == false {
            return [URL(fileURLWithPath: previewPath)]
        }
        return []
    }
    
    private static func executeAppleScript(source: String) -> [String]? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let output = script.executeAndReturnError(&error)
            if let e = error {
                Logger.shared.error("AppleScript error: \(e)")
                return nil
            }
            if output.descriptorType == typeAEList {
                var results: [String] = []
                for i in 1...output.numberOfItems {
                    if let s = output.atIndex(i)?.stringValue { results.append(s) }
                }
                return results
            } else if let s = output.stringValue {
                return [s]
            }
        }
        return nil
    }
}
