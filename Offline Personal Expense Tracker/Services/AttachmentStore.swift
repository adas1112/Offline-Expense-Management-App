import Foundation

enum AttachmentStore {
    static let maximumBytes = 8 * 1024 * 1024

    static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func save(data: Data, fileExtension: String) throws -> String {
        guard data.count <= maximumBytes else {
            throw AttachmentError.tooLarge
        }
        let name = UUID().uuidString + "." + fileExtension.filter { $0.isLetter || $0.isNumber }
        let url = try directory().appendingPathComponent(name)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }

    static func url(for fileName: String) -> URL? {
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        return try? directory().appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        guard let url = url(for: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func delete(fileName: String?) {
        guard let fileName, let url = url(for: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll() {
        guard let folder = try? directory() else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

enum AttachmentError: Error {
    case tooLarge

    var message: String {
        switch self {
        case .tooLarge:
            "Attachments must be 8 MB or smaller."
        }
    }
}
