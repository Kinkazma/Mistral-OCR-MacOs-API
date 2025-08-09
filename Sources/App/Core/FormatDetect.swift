import Foundation
import UniformTypeIdentifiers
import AppKit
import PDFKit
import QuickLookThumbnailing

enum InferenceKind { case imageURL, documentURL }

struct NormalizedInput {
    let kind: InferenceKind
    let mime: String
    let url: URL
}

enum FormatDetect {
    static func normalize(_ url: URL) throws -> NormalizedInput {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        // Document formats accepted by Mistral
        if type.conforms(to: .pdf) {
            return .init(kind: .documentURL, mime: "application/pdf", url: url)
        }
        if let docx = UTType(filenameExtension: "docx"), type.conforms(to: docx) {
            return .init(kind: .documentURL, mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", url: url)
        }
        if let pptx = UTType(filenameExtension: "pptx"), type.conforms(to: pptx) {
            return .init(kind: .documentURL, mime: "application/vnd.openxmlformats-officedocument.presentationml.presentation", url: url)
        }
        // Image formats explicitly listed
        if type == .png || type == .jpeg || type.identifier == "public.avif" {
            return .init(kind: .imageURL, mime: type.preferredMIMEType ?? "image/png", url: url)
        }
        if type.conforms(to: .image) {
            // HEIC/JP2/TIFF/BMP/WebP → PNG for safety
            let dst = try convertImageToPNG(url)
            return .init(kind: .imageURL, mime: "image/png", url: dst)
        }
        // Fallback: render to PDF
        let pdf = try renderToPDF(url)
        return .init(kind: .documentURL, mime: "application/pdf", url: pdf)
    }
    
    static func convertImageToPNG(_ src: URL) throws -> URL {
        let data = try Data(contentsOf: src)
        guard let img = NSImage(data: data) else { throw NSError(domain: "convert", code: 1) }
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "convert", code: 2)
        }
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try png.write(to: dst)
        return dst
    }
    
    static func renderToPDF(_ src: URL) throws -> URL {
        // Simple fallback: if it opens in WebView-like rendering, rasterize into a PDF page.
        let img = NSWorkspace.shared.icon(forFile: src.path)
        let pdf = PDFDocument()
        let page = PDFPage(image: img) ?? PDFPage()
        pdf.insert(page, at: 0)
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        if let data = pdf.dataRepresentation() { try data.write(to: dst) }
        return dst
    }
}
