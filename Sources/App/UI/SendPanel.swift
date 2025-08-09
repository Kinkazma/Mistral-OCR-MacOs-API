import SwiftUI

enum OutputKind: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case markdownNoImages = "Markdown (sans images)"
    case json = "JSON (Annotations)"
    var id: String { rawValue }
}

struct SendPanel: View {
    @Binding var pending: [URL]
    @State private var model: String = SettingsStore.shared.selectedModel
    @State private var output: OutputKind = .markdown
    // Whether to include images as base64 in OCR output.  This state is
    // initialized from SettingsStore and persisted back via a onChange
    // handler.
    @State private var includeImages = SettingsStore.shared.includeImages
    @State private var preserveStructure = SettingsStore.shared.preserveStructure
    @State private var isBusy = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("Right.Settings")).font(.headline)
            .padding(.top, 18)
            Picker(LocalizedStringKey("Settings.Model"), selection: $model) {
                ForEach(SettingsStore.shared.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            Picker(LocalizedStringKey("Settings.OutputFormat"), selection: $output) {
                ForEach(OutputKind.allCases) { k in Text(k.rawValue).tag(k) }
            }
            Toggle(LocalizedStringKey("Settings.IncludeImages"), isOn: $includeImages)
                .onChange(of: includeImages) { _, newValue in
                    // Persist the setting globally
                    SettingsStore.shared.includeImages = newValue
                }

            // Preserve the folder structure of dropped items when exporting OCR results.
            Toggle("Conserver la structure des dossiers", isOn: $preserveStructure)
                .onChange(of: preserveStructure) { _, newValue in
                    SettingsStore.shared.preserveStructure = newValue
                }
            
            Button {
                Task { await send() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.orange).frame(height: 42)
                    Text(NSLocalizedString("Button.Send", comment: "")).foregroundStyle(.white).bold()
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy || pending.isEmpty)
            
            Spacer()
        }
        .padding()
        .onAppear {
            model = SettingsStore.shared.selectedModel
            preserveStructure = SettingsStore.shared.preserveStructure
            includeImages = SettingsStore.shared.includeImages
        }
        .onChange(of: model) { _, newValue in SettingsStore.shared.selectedModel = newValue }
    }
    
    private func send() async {
        isBusy = true
        defer { isBusy = false }
        // Compute a common base directory for all pending items if we need to
        // preserve the folder structure.  We identify the common prefix among
        // the parent directories of all items.  If preserveStructure is false
        // the base remains empty and results will be written into the root of
        // the export folder.
        var commonBase: String = ""
        if preserveStructure, pending.count > 1 {
            let dirs = pending.map { $0.deletingLastPathComponent().path }
            // Reduce by computing the common prefix incrementally.  We ensure
            // that we only cut at path component boundaries by trimming any
            // trailing partial component after the string prefix match.
            if let first = dirs.first {
                commonBase = dirs.dropFirst().reduce(first) { acc, next in
                    var prefix = String(acc.commonPrefix(with: next))
                    // Trim to the last path separator to avoid partial component
                    if let idx = prefix.lastIndex(of: "/") {
                        prefix = String(prefix[..<idx])
                    }
                    return prefix
                }
            }
        } else if preserveStructure, let only = pending.first {
            commonBase = only.deletingLastPathComponent().path
        }
        for url in pending {
            do {
                let normalized = try FormatDetect.normalize(url)
                var result = try await OCRClient.shared.process(normalized: normalized,
                                                                model: model,
                                                                includeImages: includeImages,
                                                                outputKind: output)
                // Determine the final destination for the result.  When a
                // deposit folder is configured we mirror the behaviour of
                // DepositWatcher: results are written into the deposit
                // export directory (with optional folder structure
                // preservation).  Otherwise we write into the user‑selected
                // export folder and, if requested, preserve only the
                // structure relative to the common base.
                if let deposit = SettingsStore.shared.depositFolder, let outURL = result.outputFileURL {
                    // Compute the relative directory of the source within the deposit
                    var relDir = ""
                    if preserveStructure {
                        var path = url.deletingLastPathComponent().path
                        let root = deposit.path
                        if path.hasPrefix(root) {
                            path.removeFirst(root.count)
                        }
                        if path.hasPrefix("/") { path.removeFirst() }
                        relDir = path
                    }
                    let exportBase = SettingsStore.shared.depositExportFolder ?? deposit.appendingPathComponent("Mistral_OCR_Export", isDirectory: true)
                    let destDir = exportBase.appendingPathComponent(relDir, isDirectory: true)
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let destURL = destDir.appendingPathComponent(outURL.lastPathComponent)
                    do {
                        try FileManager.default.moveItem(at: outURL, to: destURL)
                        result = OCRResult(outputText: result.outputText, outputFileURL: destURL, pages: result.pages)
                    } catch {
                        Logger.shared.error("Failed to relocate result \(outURL.path) → \(destURL.path): \(error.localizedDescription)")
                    }
                } else if preserveStructure, let outURL = result.outputFileURL {
                    // When not using a deposit folder, optionally preserve
                    // the relative directory structure based on a common base
                    let origDir = url.deletingLastPathComponent().path
                    var relPath = origDir
                    if !commonBase.isEmpty, relPath.hasPrefix(commonBase) {
                        relPath.removeFirst(commonBase.count)
                        if relPath.hasPrefix("/") { relPath.removeFirst() }
                    } else {
                        if relPath.hasPrefix("/") { relPath.removeFirst() }
                    }
                    let destDir = SettingsStore.shared.exportFolder.appendingPathComponent(relPath, isDirectory: true)
                    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                    let destURL = destDir.appendingPathComponent(outURL.lastPathComponent)
                    do {
                        try FileManager.default.moveItem(at: outURL, to: destURL)
                        result = OCRResult(outputText: result.outputText, outputFileURL: destURL, pages: result.pages)
                    } catch {
                        Logger.shared.error("Failed to relocate result \(outURL.path) → \(destURL.path): \(error.localizedDescription)")
                    }
                }
                // Persist the OCR result into the history store.  Because HistoryStore
                // is annotated with `@MainActor` its methods must be invoked on the
                // main actor.  Use `MainActor.run` to perform the insertion from
                // within this background task; this avoids the “No 'async'
                // operations occur within 'await' expression” compiler diagnostic
                // that would arise if we simply wrote `await HistoryStore.shared.insert(...)`.
                await MainActor.run {
                    HistoryStore.shared.insert(from: url, normalized: normalized, result: result)
                }
            } catch {
                Logger.shared.error("OCR failed for \(url.path): \(error.localizedDescription)")
            }
        }
        pending.removeAll()
    }
}
