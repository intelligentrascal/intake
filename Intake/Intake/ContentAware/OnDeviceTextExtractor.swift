import AppKit
import Foundation
import ImageIO
import IntakeCore
import PDFKit
import Vision

/// Reads text out of a PDF or image on this Mac: the PDF text layer first,
/// then Vision's on-device text recognition for scanned PDFs (first 2 pages)
/// and images. Files over 50 MB and encrypted / locked PDFs are skipped.
/// Nothing here touches the network.
nonisolated struct OnDeviceTextExtractor: ContentTextExtractor {
    /// A text layer shorter than this is treated as a scan.
    static let minimumTextLayerCharacters = 40
    static let scannedPageLimit = 2
    /// Longest edge handed to text recognition.
    static let recognitionMaxPixels: CGFloat = 2_400

    @concurrent
    func text(from url: URL, maximumCharacters: Int) async -> String? {
        let size = DownloadWriteGate.fileSize(at: url)
        guard size > 0, size <= ContentAwareRenameSettings.maximumFileSize else { return nil }
        let ext = url.pathExtension.lowercased()
        if ContentAwareFileType.pdf.extensions.contains(ext) {
            return await pdfText(from: url, maximumCharacters: maximumCharacters)
        }
        if ContentAwareFileType.images.extensions.contains(ext) {
            guard let image = Self.downscaledImage(at: url) else { return nil }
            return await Self.recognizeText(in: [image], maximumCharacters: maximumCharacters)
        }
        return nil
    }

    private func pdfText(from url: URL, maximumCharacters: Int) async -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        // Never try to unlock or read around encryption.
        guard !document.isEncrypted, !document.isLocked else { return nil }

        var layer = ""
        for index in 0..<document.pageCount {
            guard layer.count < maximumCharacters else { break }
            if let text = document.page(at: index)?.string {
                layer += text + "\n"
            }
        }
        let trimmed = layer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= Self.minimumTextLayerCharacters {
            return String(trimmed.prefix(maximumCharacters))
        }

        // Scanned PDF: recognize the first pages.
        var images: [CGImage] = []
        for index in 0..<min(document.pageCount, Self.scannedPageLimit) {
            if let page = document.page(at: index), let image = Self.render(page) {
                images.append(image)
            }
        }
        let recognized = await Self.recognizeText(in: images, maximumCharacters: maximumCharacters)
        if let recognized, !recognized.isEmpty { return recognized }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(recognitionMaxPixels / max(bounds.width, bounds.height), 3)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func downscaledImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: recognitionMaxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func recognizeText(in images: [CGImage], maximumCharacters: Int) async -> String? {
        var lines: [String] = []
        var count = 0
        for image in images {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            guard let observations = try? await request.perform(on: image) else { continue }
            for observation in observations {
                guard let line = observation.topCandidates(1).first?.string else { continue }
                lines.append(line)
                count += line.count + 1
                if count >= maximumCharacters { break }
            }
            if count >= maximumCharacters { break }
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maximumCharacters))
    }
}
