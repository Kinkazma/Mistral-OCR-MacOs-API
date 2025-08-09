import Foundation

final class Logger {
    static let shared = Logger()
    private let logDir: URL
    private let fileURL: URL
    private let handle: FileHandle?
    
    init() {
        let fm = FileManager.default
        logDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MistralOCR_Desktop", isDirectory: true)
        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        fileURL = logDir.appendingPathComponent("mocr-\(stamp).log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }
    
    func info(_ s: String) { write("INFO", s) }
    func error(_ s: String) { write("ERROR", s) }
    
    private func write(_ level: String, _ s: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(level)] \(s)\n"
        if let data = line.data(using: .utf8) { try? handle?.write(contentsOf: data) }
    }
    
    func exportToDownloads() -> URL? {
        let dst = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MistralOCR_Desktop-\(Int(Date().timeIntervalSince1970)).log")
        do { try FileManager.default.copyItem(at: fileURL, to: dst); return dst } catch { return nil }
    }
}
