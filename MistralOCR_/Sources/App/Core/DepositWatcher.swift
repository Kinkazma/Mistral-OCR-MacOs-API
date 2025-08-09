import Foundation
import AppKit

/// Observes a user‑selected deposit folder and automatically processes incoming
/// documents.  When a deposit folder is configured in `SettingsStore` the
/// watcher periodically scans the folder for new files (recursively) and
/// performs OCR on each unprocessed file.  Results are written to a mirror
/// directory in the export folder and the original file is either moved to
/// a designated trash folder or placed in the system Trash.  The watcher
/// maintains a set of processed file paths to avoid reprocessing the same
/// document multiple times.
final class DepositWatcher {
    static let shared = DepositWatcher()

    /// Timer used to periodically scan the deposit directory.  We avoid
    /// DispatchSource because recursive FSEvents can be complex to manage; a
    /// simple scan every few seconds is sufficient for typical workflows.
    private var timer: Timer?
    /// Set of absolute paths that have already been processed.  Paths are
    /// removed when the deposit folder is changed or the watcher is reset.
    private var processed: Set<String> = []

    private init() {}

    /// Update internal state in response to changes in `SettingsStore`.  This
    /// method is idempotent: it cancels any existing timer and restarts
    /// scanning with the current deposit/export/trash settings.  When no
    /// deposit folder is configured the watcher is disabled.
    func updatePaths() {
        // Cancel existing timer
        timer?.invalidate()
        timer = nil
        processed.removeAll()
        guard let deposit = SettingsStore.shared.depositFolder else { return }
        // Ensure default export and trash directories exist if needed
        let fm = FileManager.default
        let export = SettingsStore.shared.depositExportFolder ?? deposit.appendingPathComponent("Mistral_OCR_Export", isDirectory: true)
        let trash = SettingsStore.shared.depositTrashFolder ?? deposit.appendingPathComponent("Mistral_OCR_Corbeille", isDirectory: true)
        // Create export directory
        do { try fm.createDirectory(at: export, withIntermediateDirectories: true) } catch {}
        // Create trash directory only if using a custom trash
        if SettingsStore.shared.useSystemTrashForSource == false {
            do { try fm.createDirectory(at: trash, withIntermediateDirectories: true) } catch {}
        }
        // Immediately perform an initial scan
        scan()
        // Schedule periodic scans every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    /// Determine if the last path component corresponds to one of the special
    /// directories used for exports or trash.  We skip these directories when
    /// scanning to avoid reprocessing our own output.
    private func isExcluded(name: String) -> Bool {
        let exportName = SettingsStore.shared.depositExportFolder?.lastPathComponent ?? "Mistral_OCR_Export"
        let trashName  = SettingsStore.shared.depositTrashFolder?.lastPathComponent  ?? "Mistral_OCR_Corbeille"
        return name == exportName || name == trashName
    }

    /// Recursively scan the deposit folder for new files.  Any file not yet
    /// recorded in `processed` will be passed to `processFile(_:)`.  Hidden
    /// files and special export/trash directories are skipped.  The scan is
    /// intentionally lightweight and tolerant of errors.
    private func scan() {
        guard let deposit = SettingsStore.shared.depositFolder else { return }
        // Attempt to access the security scope of the deposit folder.  When
        // selected via NSOpenPanel the URL should be security‑scoped.  If the call
        // succeeds we must balance it with a matching stopAccessing call.  We
        // gracefully proceed even if startAccessing returns false because some
        // file system locations (e.g. Downloads) may not require scoped
        // access.
        let accessed: Bool = deposit.startAccessingSecurityScopedResource()
        defer {
            if accessed { deposit.stopAccessingSecurityScopedResource() }
        }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: deposit,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return }
        for case let fileURL as URL in enumerator {
            do {
                let resource = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resource.isDirectory == true {
                    // Skip scanning into export and trash subdirectories
                    if isExcluded(name: fileURL.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
            } catch {
                continue
            }
            // Skip files that reside inside excluded directories
            let parentName = fileURL.deletingLastPathComponent().lastPathComponent
            if isExcluded(name: parentName) { continue }
            let path = fileURL.path
            if processed.contains(path) { continue }
            processed.insert(path)
            processFile(fileURL)
        }
    }

    /// Dispatch processing of a file asynchronously.  The heavy lifting is
    /// performed on a detached task to avoid blocking the scan timer.
    private func processFile(_ url: URL) {
        Task.detached { [url] in
            await self._processFile(url)
        }
    }

    /// Perform OCR on the given file, write the result to the appropriate
    /// export location, move or trash the original file, create an alias
    /// pointing to the original when appropriate, and insert the OCR result
    /// into the history.  Any errors encountered are logged but do not
    /// interrupt subsequent processing.
    private func _processFile(_ url: URL) async {
        do {
            // Normalize and run OCR using the same model as the interactive UI
            let normalized = try FormatDetect.normalize(url)
            let key = SettingsStore.shared.apiKey
            guard !key.isEmpty else { return }
            // Build and send request manually to avoid writing into the normal export folder
            struct Doc: Encodable { let type: String; let document_url: String?; let image_url: String? }
            struct Request: Encodable { let model: String; let document: Doc; let include_image_base64: Bool }
            let bytes = try Data(contentsOf: normalized.url)
            let b64 = bytes.base64EncodedString()
            let mime = normalized.mime
            let doc: Doc
            switch normalized.kind {
            case .documentURL:
                doc = Doc(type: "document_url", document_url: "data:\(mime);base64,\(b64)", image_url: nil)
            case .imageURL:
                doc = Doc(type: "image_url", document_url: nil, image_url: "data:\(mime);base64,\(b64)")
            }
            let reqBody = Request(model: SettingsStore.shared.selectedModel,
                                  document: doc,
                                  include_image_base64: SettingsStore.shared.includeImages)
            var req = URLRequest(url: URL(string: "https://api.mistral.ai/v1/ocr")!)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            req.addValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(reqBody)
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                let err = String(data: data, encoding: .utf8) ?? "HTTP error"
                throw NSError(domain: "ocr", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: err])
            }
            let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let pagesArr = (decoded?["pages"] as? [[String: Any]]) ?? []
            let md = pagesArr.compactMap { $0["markdown"] as? String }.joined(separator: "\n\n")
            let pageCount = pagesArr.count
            // Determine relative path within the deposit folder to replicate directory structure
            guard let deposit = SettingsStore.shared.depositFolder else { return }
            let root = deposit.path
            var relPath = url.path
            if relPath.hasPrefix(root) {
                relPath.removeFirst(root.count)
            }
            if relPath.hasPrefix("/") { relPath.removeFirst() }
            let relativeDir = (relPath as NSString).deletingLastPathComponent
            // Compute export directory and ensure it exists
            let exportBase = SettingsStore.shared.depositExportFolder ?? deposit.appendingPathComponent("Mistral_OCR_Export", isDirectory: true)
            let destDir = exportBase.appendingPathComponent(relativeDir, isDirectory: true)
            do { try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true) } catch {}
            // Write markdown result to file; use original basename with .md extension
            let baseName = url.deletingPathExtension().lastPathComponent
            let destFile = destDir.appendingPathComponent(baseName + ".md")
            do {
                try md.data(using: .utf8)?.write(to: destFile)
            } catch {
                Logger.shared.error("Failed to write OCR result to \(destFile.path): \(error.localizedDescription)")
            }
            // Move the original file to either the system trash or a custom trash directory
            var movedURL: URL? = nil
            if SettingsStore.shared.useSystemTrashForSource {
                var res: NSURL? = nil
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: &res)
                    movedURL = res as URL?
                } catch {
                    Logger.shared.error("Failed to move \(url.path) to system trash: \(error.localizedDescription)")
                    movedURL = nil
                }
            } else {
                let trashBase = SettingsStore.shared.depositTrashFolder ?? deposit.appendingPathComponent("Mistral_OCR_Corbeille", isDirectory: true)
                let destTrashDir = trashBase.appendingPathComponent(relativeDir, isDirectory: true)
                do { try FileManager.default.createDirectory(at: destTrashDir, withIntermediateDirectories: true) } catch {}
                let destTrashFile = destTrashDir.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.moveItem(at: url, to: destTrashFile)
                    movedURL = destTrashFile
                } catch {
                    Logger.shared.error("Failed to move \(url.path) to deposit trash: \(error.localizedDescription)")
                    movedURL = nil
                }
            }
            // If we moved the file and are not using system trash, create an alias alongside the md result
            if let moved = movedURL, !SettingsStore.shared.useSystemTrashForSource {
                let aliasPath = destDir.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createSymbolicLink(at: aliasPath, withDestinationURL: moved)
                } catch {
                    // it's fine if alias creation fails; we log and continue
                    Logger.shared.error("Failed to create alias for \(moved.path): \(error.localizedDescription)")
                }
            }
            // Record the OCR result into history with a new OCRResult reflecting our destFile.
            // Since HistoryStore is marked @MainActor, we must perform the insert via
            // MainActor.run.  This ensures the insert occurs on the main thread and
            // avoids publishing changes from a background thread.
            let newResult = OCRResult(outputText: md, outputFileURL: destFile, pages: pageCount)
            await MainActor.run {
                HistoryStore.shared.insert(from: url, normalized: normalized, result: newResult)
            }
        } catch {
            Logger.shared.error("Deposit processing failed for \(url.path): \(error.localizedDescription)")
        }
    }
}