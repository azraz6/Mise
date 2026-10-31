import Foundation
import UIKit
import Vision

enum OCRServiceError: Error, Equatable {
    case noImages
    case unreadableImage
    case noText
}

struct OCRPageResult: Identifiable, Sendable {
    var id = UUID()
    var pageIndex: Int
    var text: String
}

final class OCRService {
    static let shared = OCRService()

    func recognizeText(in images: [UIImage]) async throws -> [OCRPageResult] {
        guard !images.isEmpty else { throw OCRServiceError.noImages }
        var results: [OCRPageResult] = []
        for (index, image) in images.enumerated() {
            try Task.checkCancellation()
            let normalized = Self.downsampled(image, maxDimension: 2600)
            guard let cgImage = normalized.cgImage else { throw OCRServiceError.unreadableImage }
            let text = try await Self.recognize(cgImage: cgImage)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(OCRPageResult(pageIndex: index, text: text))
            }
        }
        guard !results.isEmpty else { throw OCRServiceError.noText }
        return results
    }

    static func combinedText(from pages: [OCRPageResult]) -> String {
        pages.sorted { $0.pageIndex < $1.pageIndex }
            .map(\.text)
            .joined(separator: "\n\n")
    }

    private static func recognize(cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            do {
                try handler.perform([request])
            } catch {
                throw OCRServiceError.unreadableImage
            }
            guard let observations = request.results, !observations.isEmpty else {
                throw OCRServiceError.noText
            }
            let sorted = observations.sorted { lhs, rhs in
                let lhsY = lhs.boundingBox.midY
                let rhsY = rhs.boundingBox.midY
                if abs(lhsY - rhsY) > 0.012 { return lhsY > rhsY }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            let lines = sorted.compactMap { observation -> String? in
                observation.topCandidates(1).first?.string
            }
            return lines.joined(separator: "\n")
        }.value
    }

    private static func downsampled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }
        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
