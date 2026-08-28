import Foundation

enum PipoResources {
    private static let bundleName = "Pipo_PipoUI.bundle"

    static var bundleURL: URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        var searchRoots = [Bundle.main.bundleURL]
        if let resourceURL = Bundle.main.resourceURL { searchRoots.append(resourceURL) }
        if let executableURL = Bundle.main.executableURL {
            searchRoots.append(executableURL.deletingLastPathComponent())
        }
        for root in searchRoots {
            var directory = root
            for _ in 0..<5 {
                candidates.append(directory.appendingPathComponent(bundleName, isDirectory: true))
                directory.deleteLastPathComponent()
            }
        }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    static func url(
        forResource name: String,
        withExtension fileExtension: String? = nil,
        subdirectory: String? = nil
    ) -> URL? {
        guard var url = bundleURL else { return nil }
        if let subdirectory {
            url.appendPathComponent(subdirectory, isDirectory: true)
        }
        url.appendPathComponent(name)
        if let fileExtension {
            url.appendPathExtension(fileExtension)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
