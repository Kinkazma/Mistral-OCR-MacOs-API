import Foundation
import AppKit
import QuickLookThumbnailing

struct OcrItem: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let displayTitle: String
    let sourceBookmark: Data
    let symlinkPath: String
    let outputKind: String
    var outputText: String?
    var outputPath: String?
}

// Mark the history store as running on the main actor.  All mutations of
// the `items` array and notifications via `objectWillChange` will occur
// on the main thread, avoiding warnings about publishing from a
// background thread.  Methods on this actor can be awaited from
// background tasks.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private let storeURL: URL
    @Published private var items: [OcrItem] = []
    
    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MistralOCR_Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storeURL = support.appendingPathComponent("history.json")
        load()
    }
    
    func insert(from original: URL, normalized: NormalizedInput, result: OCRResult) {
        let bookmark = try? original.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let linkDir = storeURL.deletingLastPathComponent().appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let item = OcrItem(id: UUID(), createdAt: Date(),
                           displayTitle: original.lastPathComponent,
                           sourceBookmark: bookmark ?? Data(),
                           symlinkPath: link.path,
                           outputKind: "markdown",
                           outputText: result.outputText,
                           outputPath: result.outputFileURL?.path)
        items.insert(item, at: 0)
        save()
        objectWillChange.send()
    }
    
    func fetchAll() -> [OcrItem] { items }
    func fetchLast(limit: Int) -> [OcrItem] { Array(items.prefix(limit)) }
    func item(id: UUID) -> OcrItem? { items.first(where: { $0.id == id }) }
    
    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
        objectWillChange.send()
    }
    
    func wipeAll() {
        items.removeAll()
        save()
        objectWillChange.send()
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        if let decoded = try? JSONDecoder().decode([OcrItem].self, from: data) { items = decoded }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: storeURL) }
    }
}

extension OcrItem {
    func resolvedURL() -> URL? {
        var isStale = false
        guard sourceBookmark.isEmpty == false,
              let url = try? URL(resolvingBookmarkData: sourceBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return url
    }
    func thumbnail() -> NSImage? {
        guard let url = resolvedURL() else { return nil }
        let size = CGSize(width: 20, height: 20)
        let req = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .icon)
        var result: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let cg = rep?.cgImage { result = NSImage(cgImage: cg, size: .init(width: size.width, height: size.height)) }
        }
        return result
    }
}
