import SwiftUI
import AppKit

struct DropZoneView: View {
    @Binding var pending: [URL]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20))
                Text("Déposez ici vos fichiers").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.bottom, 6)
            List {
                ForEach(Array(pending.enumerated()), id: \.offset) { idx, url in
                    HStack {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Button {
                            pending.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 220)
            Spacer()
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // Iterate over dropped objects.  For each URL we either enqueue it or, if the user has
            // opted into auto‑send, immediately process it via the OCR engine.  Note: loading
            // asynchronous objects off the main queue and dispatching back ensures UI updates are
            // thread‑safe.
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let droppedURL = url else { return }
                    DispatchQueue.main.async {
                        if SettingsStore.shared.autoSendOnDrop {
                            // Immediately perform OCR on the dropped file using the current
                            // settings.  We choose Markdown output with images to match the
                            // default SendPanel.  Any errors are logged.
                            Task {
                                do {
                                    let normalized = try FormatDetect.normalize(droppedURL)
                                    let result = try await OCRClient.shared.process(normalized: normalized,
                                                                                    model: SettingsStore.shared.selectedModel,
                                                                                    includeImages: SettingsStore.shared.includeImages,
                                                                                    outputKind: .markdown)
                                    await MainActor.run {
                                        HistoryStore.shared.insert(from: droppedURL, normalized: normalized, result: result)
                                    }
                                    // Copy result text to clipboard for convenience
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(result.outputText, forType: .string)
                                } catch {
                                    Logger.shared.error("Auto‑send OCR failed: \(error.localizedDescription)")
                                }
                            }
                        } else {
                            // Append to the queue for manual sending via the SendPanel
                            pending.append(droppedURL)
                        }
                    }
                }
            }
            return true
        }
        .padding()
    }
}
