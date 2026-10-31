import UIKit
import XCTest
@testable import Mise

final class ImageStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ImageStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiseImageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ImageStore(baseDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    func testStoreAndLoadImage() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let filename = try await store.store(image: image)
        XCTAssertTrue(filename.hasSuffix(".jpg"))
        let loaded = await store.loadImage(named: filename)
        XCTAssertNotNil(loaded)
        store.deleteImage(named: filename)
        let afterDelete = await store.loadImage(named: filename)
        XCTAssertNil(afterDelete)
    }

    func testScratchFilesAndCleanup() throws {
        let filename = try store.storeScratchImage(data: Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(store.scratchImageData(named: filename), Data([0x01, 0x02, 0x03]))

        let path = store.scratchImageURL(named: filename)
        let oldDate = Date().addingTimeInterval(-10 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path.path)
        store.cleanScratchFiles(olderThan: 7)
        XCTAssertNil(store.scratchImageData(named: filename))
    }

    func testScratchCleanupKeepsRecentFiles() throws {
        let filename = try store.storeScratchImage(data: Data([0x04]))
        store.cleanScratchFiles(olderThan: 7)
        XCTAssertEqual(store.scratchImageData(named: filename), Data([0x04]))
        store.deleteScratchImage(named: filename)
        XCTAssertNil(store.scratchImageData(named: filename))
    }

    func testDownsamplingLimitsLongestEdge() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let resized = ImageStore.downsample(image, maxDimension: 100)
        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), 100.5)
        XCTAssertEqual(resized.size.width / resized.size.height, 2, accuracy: 0.05)
    }

    func testUnsafeImageURLIsRejectedWithoutNetwork() async {
        do {
            _ = try await store.downloadAndStoreImage(from: URL(string: "http://127.0.0.1/cover.jpg")!)
            XCTFail("Private hosts must not be fetched")
        } catch let error as ImageStoreError {
            switch error {
            case .downloadFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
