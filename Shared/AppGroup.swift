import Foundation

enum MiseAppGroup {
    static let identifier = "group.com.elahitech.mise"
    static let importQueueFolder = "ImportQueue"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

struct SharedImportRequest: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case url
        case text
        case image
    }

    var id: UUID
    var createdAt: Date
    var kind: Kind
    var urlString: String?
    var text: String?
    var imageFilenames: [String]
    var suggestedSourceType: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: Kind,
        urlString: String? = nil,
        text: String? = nil,
        imageFilenames: [String] = [],
        suggestedSourceType: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.urlString = urlString
        self.text = text
        self.imageFilenames = imageFilenames
        self.suggestedSourceType = suggestedSourceType
    }
}

struct SharedImportStore {
    let directory: URL

    init?(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let container = MiseAppGroup.containerURL {
            self.directory = container.appendingPathComponent(MiseAppGroup.importQueueFolder, isDirectory: true)
        } else {
            return nil
        }
    }

    private var imagesDirectory: URL {
        directory.appendingPathComponent("Images", isDirectory: true)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    func enqueue(_ request: SharedImportRequest, imageData: [Data] = []) throws -> SharedImportRequest {
        try prepare()
        var stored = request
        var filenames: [String] = []
        for data in imageData {
            let filename = "\(stored.id.uuidString)-\(UUID().uuidString).jpg"
            let url = imagesDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            filenames.append(filename)
        }
        stored.imageFilenames.append(contentsOf: filenames)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(stored)
        let requestURL = directory.appendingPathComponent("\(stored.id.uuidString).json")
        try data.write(to: requestURL, options: .atomic)
        return stored
    }

    func pendingRequests() -> [SharedImportRequest] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SharedImportRequest? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SharedImportRequest.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func imageData(for filename: String) -> Data? {
        try? Data(contentsOf: imagesDirectory.appendingPathComponent(filename))
    }

    func imageURL(for filename: String) -> URL {
        imagesDirectory.appendingPathComponent(filename)
    }

    func remove(_ request: SharedImportRequest) {
        let requestURL = directory.appendingPathComponent("\(request.id.uuidString).json")
        try? FileManager.default.removeItem(at: requestURL)
        for filename in request.imageFilenames {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(filename))
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? prepare()
    }
}
