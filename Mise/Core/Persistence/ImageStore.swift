import Foundation
import UIKit

final class ImageStore {
    static let shared = ImageStore()

    private let coversDirectory: URL
    private let scratchDirectory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mise", isDirectory: true)
        coversDirectory = base.appendingPathComponent("Covers", isDirectory: true)
        scratchDirectory = base.appendingPathComponent("ImportScratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        cache.countLimit = 80
    }

    func url(for filename: String) -> URL {
        coversDirectory.appendingPathComponent(filename)
    }

    func store(image: UIImage) async throws -> String {
        let data = await Task.detached(priority: .userInitiated) { () -> Data? in
            let resized = Self.downsample(image, maxDimension: 1600)
            return resized.jpegData(compressionQuality: 0.82)
        }.value
        guard let data else { throw ImageStoreError.encodingFailed }
        return try store(data: data, fileExtension: "jpg")
    }

    func store(data: Data, fileExtension: String = "jpg") throws -> String {
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let destination = coversDirectory.appendingPathComponent(filename)
        try data.write(to: destination, options: .atomic)
        return filename
    }

    func loadImage(named filename: String) async -> UIImage? {
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        let url = coversDirectory.appendingPathComponent(filename)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }.value
        if let image { cache.setObject(image, forKey: filename as NSString) }
        return image
    }

    func downloadAndStoreImage(from url: URL) async throws -> String {
        guard SourceDetector.isSafeRemoteURL(url) else { throw ImageStoreError.downloadFailed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mise/1.0 (iPhone)", forHTTPHeaderField: "User-Agent")
        let redirects = SafeRedirectDelegate()
        let (data, response) = try await URLSession.shared.data(for: request, delegate: redirects)
        if redirects.blockedURL != nil { throw ImageStoreError.downloadFailed }
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalURL = http.url,
              SourceDetector.isSafeRemoteURL(finalURL) else {
            throw ImageStoreError.downloadFailed
        }
        guard data.count <= 10 * 1024 * 1024 else { throw ImageStoreError.tooLarge }
        guard let image = UIImage(data: data) else { throw ImageStoreError.invalidImage }
        return try await store(image: image)
    }

    func deleteImage(named filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        cache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: coversDirectory.appendingPathComponent(filename))
    }

    // MARK: - Import scratch files

    func storeScratchImage(data: Data) throws -> String {
        let filename = "\(UUID().uuidString).jpg"
        try data.write(to: scratchDirectory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func scratchImageData(named filename: String) -> Data? {
        try? Data(contentsOf: scratchDirectory.appendingPathComponent(filename))
    }

    func scratchImageURL(named filename: String) -> URL {
        scratchDirectory.appendingPathComponent(filename)
    }

    func deleteScratchImage(named filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: scratchDirectory.appendingPathComponent(filename))
    }

    func cleanScratchFiles(olderThan days: Int = 7) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scratchDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let date = values.contentModificationDate, date < cutoff else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    static func downsample(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

enum ImageStoreError: Error {
    case encodingFailed
    case downloadFailed
    case tooLarge
    case invalidImage
}
