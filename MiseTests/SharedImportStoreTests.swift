import XCTest
@testable import Mise

final class SharedImportStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiseShareTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
    }

    func testEnqueuePersistsURLRequest() throws {
        let store = try XCTUnwrap(SharedImportStore(directory: directory))
        let request = SharedImportRequest(kind: .url, urlString: "https://example.com/recipe")
        let stored = try store.enqueue(request)
        XCTAssertEqual(stored.id, request.id)

        let pending = store.pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.urlString, "https://example.com/recipe")
        XCTAssertEqual(pending.first?.kind, .url)
    }

    func testEnqueueStoresImagesAndRemovesThem() throws {
        let store = try XCTUnwrap(SharedImportStore(directory: directory))
        let request = SharedImportRequest(kind: .image)
        let stored = try store.enqueue(request, imageData: [Data([0x01, 0x02]), Data([0x03])])
        XCTAssertEqual(stored.imageFilenames.count, 2)
        XCTAssertEqual(store.imageData(for: stored.imageFilenames[0]), Data([0x01, 0x02]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: stored.imageFilenames[0]).path))

        store.remove(stored)
        XCTAssertTrue(store.pendingRequests().isEmpty)
        XCTAssertNil(store.imageData(for: stored.imageFilenames[0]))
    }

    func testPendingRequestsAreSortedOldestFirst() throws {
        let store = try XCTUnwrap(SharedImportStore(directory: directory))
        let newer = SharedImportRequest(createdAt: Date(), kind: .text, text: "new")
        let older = SharedImportRequest(createdAt: Date().addingTimeInterval(-60), kind: .text, text: "old")
        _ = try store.enqueue(newer)
        _ = try store.enqueue(older)
        XCTAssertEqual(store.pendingRequests().map(\.text), ["old", "new"])
    }

    func testRemoveAllClearsQueue() throws {
        let store = try XCTUnwrap(SharedImportStore(directory: directory))
        _ = try store.enqueue(SharedImportRequest(kind: .text, text: "one"))
        _ = try store.enqueue(SharedImportRequest(kind: .text, text: "two"))
        XCTAssertEqual(store.pendingRequests().count, 2)
        store.removeAll()
        XCTAssertTrue(store.pendingRequests().isEmpty)
    }

    func testMalformedJSONIsSkipped() throws {
        let store = try XCTUnwrap(SharedImportStore(directory: directory))
        _ = try store.enqueue(SharedImportRequest(kind: .url, urlString: "https://example.com"))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        XCTAssertEqual(store.pendingRequests().count, 1)
    }
}
